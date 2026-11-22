import SwiftUI

/// Settings for the EcoFlow power station: the two API keys from the EcoFlow developer portal
/// (kept in the Keychain) and the serial number of the station to watch.
@MainActor
final class EcoFlowSettingsModel: ObservableObject {
    /// Typed in now; empty means "keep whatever is already in the Keychain".
    @Published var accessKey = ""
    @Published var secretKey = ""
    @Published var serial = AppSettings.ecoFlowSerial
    @Published var name = AppSettings.ecoFlowName
    @Published var region = AppSettings.ecoFlowRegion
    @Published private(set) var hasKeys = AppSettings.ecoFlowConfigKeysStored
    @Published private(set) var devices: [EcoFlowClient.Device] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    var canSave: Bool {
        (hasKeys || (!accessKey.isEmpty && !secretKey.isEmpty))
            && !serial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Stores the keys in the Keychain, the rest in `UserDefaults`, and polls the station right away.
    func save() {
        if !accessKey.isEmpty { Keychain.set(accessKey, account: AppSettings.ecoFlowAccessKeyAccount) }
        if !secretKey.isEmpty { Keychain.set(secretKey, account: AppSettings.ecoFlowSecretKeyAccount) }
        accessKey = ""
        secretKey = ""
        hasKeys = AppSettings.ecoFlowConfigKeysStored

        AppSettings.ecoFlowSerial = serial
        AppSettings.ecoFlowName = name
        AppSettings.ecoFlowRegion = region
        error = nil
        refresh()
    }

    /// Forgets the keys; the serial number and the name stay.
    func clearKeys() {
        Keychain.set("", account: AppSettings.ecoFlowAccessKeyAccount)
        Keychain.set("", account: AppSettings.ecoFlowSecretKeyAccount)
        accessKey = ""
        secretKey = ""
        devices = []
        hasKeys = false
        refresh()
    }

    func refresh() {
        Task {
            await EcoFlowService.shared.invalidate()
            DeviceBatteryStore.shared.refresh()
        }
    }

    /// Lists the stations bound to the account, so the serial number can be picked instead of typed.
    func loadDevices() {
        guard !isLoading else { return }
        // Keys typed just now win, so the list can be tried before saving them.
        let access = accessKey.isEmpty ? Keychain.string(AppSettings.ecoFlowAccessKeyAccount) : accessKey
        let secret = secretKey.isEmpty ? Keychain.string(AppSettings.ecoFlowSecretKeyAccount) : secretKey
        guard let access, let secret else {
            error = tr("Enter both keys first.", "Сначала введите оба ключа.")
            return
        }

        isLoading = true
        error = nil
        let client = EcoFlowClient(region: region, accessKey: access, secretKey: secret)
        Task { @MainActor in
            do {
                devices = try await client.devices()
                if devices.isEmpty {
                    error = tr("No devices on this account.", "На этом аккаунте нет устройств.")
                } else if serial.isEmpty, let first = devices.first {
                    serial = first.serial
                    if name.isEmpty { name = first.name }
                }
            } catch {
                devices = []
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}

struct EcoFlowSettingsSection: View {
    @ObservedObject var batteries: DeviceBatteryStore
    @AppStorage(AppSettings.ecoFlowEnabledKey) private var enabled = false
    @StateObject private var model = EcoFlowSettingsModel()

    var body: some View {
        Section("EcoFlow") {
            Toggle(tr("Show the charge of an EcoFlow power station", "Показывать заряд зарядной станции EcoFlow"), isOn: $enabled)
            if enabled {
                Picker(tr("Region", "Регион"), selection: $model.region) {
                    ForEach(EcoFlowClient.Region.allCases) { Text($0.title).tag($0) }
                }

                SecureField(tr("Access key", "Access key"), text: $model.accessKey, prompt: Text(keyPrompt))
                SecureField(tr("Secret key", "Secret key"), text: $model.secretKey, prompt: Text(keyPrompt))

                LabeledContent(tr("Station", "Станция")) {
                    HStack(spacing: 8) {
                        if model.devices.isEmpty {
                            TextField(tr("Serial number", "Серийный номер"), text: $model.serial)
                                .frame(minWidth: 160)
                        } else {
                            Picker("", selection: $model.serial) {
                                ForEach(model.devices) { device in
                                    Text(device.online ? device.name : tr("\(device.name) (offline)", "\(device.name) (не в сети)"))
                                        .tag(device.serial)
                                }
                            }
                            .labelsHidden()
                        }
                        Button(tr("Find", "Найти"), action: model.loadDevices)
                            .disabled(model.isLoading)
                        if model.isLoading {
                            ProgressView().controlSize(.small)
                        }
                    }
                }

                TextField(tr("Name in the island", "Название в острове"), text: $model.name, prompt: Text("EcoFlow"))

                HStack {
                    Spacer()
                    if model.hasKeys {
                        Button(tr("Forget Keys", "Забыть ключи"), action: model.clearKeys)
                    }
                    Button(tr("Save", "Сохранить"), action: model.save)
                        .disabled(!model.canSave)
                }

                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                statusRow

                Text(tr(
                    "Create an access key and a secret key at developer.ecoflow.com (the account the station is registered to), pick the matching region, then press Find to choose the station. The keys are kept in the Keychain; the charge is refreshed every 5 minutes.",
                    "Создайте access key и secret key на developer.ecoflow.com (в том аккаунте, где зарегистрирована станция), выберите тот же регион и нажмите «Найти», чтобы выбрать станцию. Ключи хранятся в Связке ключей, заряд обновляется каждые 5 минут."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var keyPrompt: String {
        model.hasKeys ? tr("Saved — type to replace", "Сохранён — введите, чтобы заменить") : tr("Required", "Обязательно")
    }

    @ViewBuilder
    private var statusRow: some View {
        switch batteries.ecoFlowStatus {
        case .off:
            EmptyView()
        case .needsCredentials:
            Label(tr("Keys or serial number are still missing.", "Не хватает ключей или серийного номера."), systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        case .ready(let date):
            Label {
                Text(tr("Updated ", "Обновлено ")) + Text(date, format: .relative(presentation: .named))
            } icon: {
                Image(systemName: "checkmark.circle")
            }
            .font(.caption)
            .foregroundStyle(.green)
        }
    }
}
