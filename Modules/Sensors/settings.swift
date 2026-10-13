//
//  settings.swift
//  Sensors
//
//  Created by Serhiy Mytrovtsiy on 23/06/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class Settings: NSStackView, Settings_v {
    private var updateIntervalValue: Int = 3
    private var hidState: Bool
    private var fanSpeedState: Bool = false
    private var fansSyncState: Bool = false
    private var unknownSensorsState: Bool = false
    private var fanValueState: FanValue = .percentage
    private var widgets: [widget_t] = []
    private enum MiniLabelMode: String {
        case valueOnly = "valueOnly"
        case labelAndValue = "labelAndValue"
    }
    
    private enum MiniLabelTextStyle: String {
        case sensorName = "sensorName"
        case shortLetters = "shortLetters"
        case firstLetter = "firstLetter"
    }
    
    public var callback: (() -> Void) = {}
    public var HIDcallback: (() -> Void) = {}
    public var unknownCallback: (() -> Void) = {}
    public var setInterval: ((_ value: Int) -> Void) = {_ in }
    public var selectedHandler: (String) -> Void = {_ in }
    
    private let title: String
    private var list: [Sensor_p] = []
    private var sensorsPrefs: PreferencesSection?
    private var selectedSensor: String = "Average System Total"
    private var miniLabelMode: MiniLabelMode = .labelAndValue
    private var miniLabelTextStyle: MiniLabelTextStyle = .sensorName
    
    public init(_ module: ModuleType) {
        self.title = module.stringValue
        self.hidState = SystemKit.shared.device.platform == .m1 ? true : false
        
        super.init(frame: NSRect.zero)
        self.orientation = .vertical
        self.spacing = Constants.Settings.margin
        
        self.updateIntervalValue = Store.shared.int(key: "\(self.title)_updateInterval", defaultValue: self.updateIntervalValue)
        self.hidState = Store.shared.bool(key: "\(self.title)_hid", defaultValue: self.hidState)
        self.fanSpeedState = Store.shared.bool(key: "\(self.title)_speed", defaultValue: self.fanSpeedState)
        self.fansSyncState = Store.shared.bool(key: "\(self.title)_fansSync", defaultValue: self.fansSyncState)
        self.unknownSensorsState = Store.shared.bool(key: "\(self.title)_unknown", defaultValue: self.unknownSensorsState)
        self.fanValueState = FanValue(rawValue: Store.shared.string(key: "\(self.title)_fanValue", defaultValue: self.fanValueState.rawValue)) ?? .percentage
        self.selectedSensor = Store.shared.string(key: "\(self.title)_sensor", defaultValue: self.selectedSensor)
        self.miniLabelMode = MiniLabelMode(rawValue: Store.shared.string(key: "\(self.title)_miniLabelMode", defaultValue: MiniLabelMode.labelAndValue.rawValue)) ?? .labelAndValue
        self.miniLabelTextStyle = MiniLabelTextStyle(rawValue: Store.shared.string(key: "\(self.title)_miniLabelTextStyle", defaultValue: MiniLabelTextStyle.sensorName.rawValue)) ?? .sensorName
        
        self.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Update interval"), component: selectView(
                action: #selector(self.changeUpdateInterval),
                items: ReaderUpdateIntervals,
                selected: "\(self.updateIntervalValue)"
            ))
        ]))
        
        self.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Fan value"), component: selectView(
                action: #selector(self.toggleFanValue),
                items: FanValues,
                selected: self.fanValueState.rawValue
            )),
            PreferencesRow(localizedString("Save the fan speed"), component: switchView(
                action: #selector(self.toggleSpeedState),
                state: self.fanSpeedState
            )),
            PreferencesRow(localizedString("Synchronize fan's control"), component: switchView(
                action: #selector(self.toggleFansSync),
                state: self.fansSyncState
            ))
        ]))
        
        var sensorsRows: [PreferencesRow] = [
            PreferencesRow(localizedString("Show unknown sensors"), component: switchView(
                action: #selector(self.toggleuUnknownSensors),
                state: self.unknownSensorsState
            ))
        ]
        if isARM {
            sensorsRows.append(PreferencesRow(localizedString("HID sensors"), component: switchView(
                action: #selector(self.toggleHID),
                state: self.hidState
            )))
        }
        sensorsRows.append(PreferencesRow(localizedString("Sensor to show"), id: "active_sensor", component: selectView(
            action: #selector(self.handleSelection),
            items: [],
            selected: self.selectedSensor)
        ))
        sensorsRows.append(PreferencesRow(localizedString("Menu bar view"), id: "mini_label_mode", component: selectView(
            action: #selector(self.changeMiniLabelMode),
            items: [
                KeyValue_t(key: MiniLabelMode.valueOnly.rawValue, value: localizedString("Value only")),
                KeyValue_t(key: MiniLabelMode.labelAndValue.rawValue, value: localizedString("Label + value"))
            ],
            selected: self.miniLabelMode.rawValue
        )))
        
        sensorsRows.append(PreferencesRow(localizedString("Menu bar label text"), id: "mini_label_text_style", component: selectView(
            action: #selector(self.changeMiniLabelTextStyle),
            items: [
                KeyValue_t(key: MiniLabelTextStyle.sensorName.rawValue, value: localizedString("Sensor name")),
                KeyValue_t(key: MiniLabelTextStyle.shortLetters.rawValue, value: localizedString("A/B/C letters")),
                KeyValue_t(key: MiniLabelTextStyle.firstLetter.rawValue, value: localizedString("First letter only"))
            ],
            selected: self.miniLabelTextStyle.rawValue
        )))
        let sensorsPrefs = PreferencesSection(sensorsRows)
        self.sensorsPrefs = sensorsPrefs
        self.addArrangedSubview(sensorsPrefs)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func load(widgets: [widget_t]) {
        self.widgets = widgets
        var sensors = self.list
        guard !sensors.isEmpty else {
            return
        }
        if !self.unknownSensorsState {
            sensors = sensors.filter({ $0.group != .unknown })
        }
        
        self.subviews.filter({ $0.identifier == NSUserInterfaceItemIdentifier("sensor") }).forEach { v in
            v.removeFromSuperview()
        }
        
        var types: [SensorType] = []
        sensors.forEach { (s: Sensor_p) in
            if !types.contains(s.type) {
                types.append(s.type)
            }
        }
        
        var buttonList: [KeyValue_t] = []
        types.forEach { (typ: SensorType) in
            let section = PreferencesSection(title: localizedString(typ.rawValue))
            section.identifier = NSUserInterfaceItemIdentifier("sensor")
            
            let filtered = sensors.filter{ $0.type == typ }
            var groups: [SensorGroup] = []
            filtered.forEach { (s: Sensor_p) in
                if !groups.contains(s.group) {
                    groups.append(s.group)
                }
            }
            groups.forEach { (group: SensorGroup) in
                filtered.filter{ $0.group == group }.forEach { (s: Sensor_p) in
                    let btn = switchView(
                        action: #selector(self.toggleSensor),
                        state: s.state
                    )
                    btn.identifier = NSUserInterfaceItemIdentifier(rawValue: s.key)
                    section.add(PreferencesRow(localizedString(s.name), component: btn))
                    buttonList.append(KeyValue_t(key: s.key, value: "\(localizedString(typ.rawValue)) - \(s.name)"))
                }
            }
            
            self.addArrangedSubview(section)
        }
        
        if let row = self.sensorsPrefs?.findRow("active_sensor") {
            self.sensorsPrefs?.setRowVisibility(row, newState: widgets.contains(where: { $0 == .mini }))
            row.replaceComponent(with: selectView(
                action: #selector(self.handleSelection),
                items: buttonList,
                selected: self.selectedSensor
            ))
        }
        
        if let row = self.sensorsPrefs?.findRow("mini_label_mode"), !widgets.isEmpty {
            self.sensorsPrefs?.setRowVisibility(row, newState: widgets.contains(where: { $0 == .mini }))
        }
        
        if let row = self.sensorsPrefs?.findRow("mini_label_text_style"), !widgets.isEmpty {
            self.sensorsPrefs?.setRowVisibility(row, newState: widgets.contains(where: { $0 == .mini || $0 == .stack }))
        }
    }
    
    public func setList(_ list: [Sensor_p]?) {
        guard let list else { return }
        self.list = self.unknownSensorsState ? list : list.filter({ $0.group != .unknown })
        self.load(widgets: self.widgets)
    }
    
    @objc private func toggleSensor(_ sender: NSControl) {
        guard let id = sender.identifier else { return }
        Store.shared.set(key: "sensor_\(id.rawValue)", value: controlState(sender))
        self.callback()
    }
    @objc private func changeUpdateInterval(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let value = Int(key) else { return }
        self.updateIntervalValue = value
        Store.shared.set(key: "\(self.title)_updateInterval", value: value)
        self.setInterval(value)
    }
    @objc private func toggleSpeedState(_ sender: NSControl) {
        self.fanSpeedState = controlState(sender)
        Store.shared.set(key: "\(self.title)_speed", value: self.fanSpeedState)
        self.callback()
    }
    @objc private func toggleHID(_ sender: NSControl) {
        self.hidState = controlState(sender)
        Store.shared.set(key: "\(self.title)_hid", value: self.hidState)
        self.HIDcallback()
    }
    @objc private func toggleFansSync(_ sender: NSControl) {
        self.fansSyncState = controlState(sender)
        Store.shared.set(key: "\(self.title)_fansSync", value: self.fansSyncState)
    }
    @objc private func toggleuUnknownSensors(_ sender: NSControl) {
        self.unknownSensorsState = controlState(sender)
        Store.shared.set(key: "\(self.title)_unknown", value: self.unknownSensorsState)
        self.unknownCallback()
    }
    @objc private func toggleFanValue(_ sender: NSMenuItem) {
        if let key = sender.representedObject as? String, let value = FanValue(rawValue: key) {
            self.fanValueState = value
            Store.shared.set(key: "\(self.title)_fanValue", value: self.fanValueState.rawValue)
            self.callback()
        }
    }
    @objc private func handleSelection(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem, let id = item.representedObject as? String else { return }
        self.selectedSensor = id
        Store.shared.set(key: "\(self.title)_sensor", value: self.selectedSensor)
        self.selectedHandler(self.selectedSensor)
    }
    
    @objc private func changeMiniLabelMode(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let mode = MiniLabelMode(rawValue: key) else { return }
        self.miniLabelMode = mode
        Store.shared.set(key: "\(self.title)_miniLabelMode", value: self.miniLabelMode.rawValue)
        self.callback()
    }
    
    @objc private func changeMiniLabelTextStyle(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let style = MiniLabelTextStyle(rawValue: key) else { return }
        self.miniLabelTextStyle = style
        Store.shared.set(key: "\(self.title)_miniLabelTextStyle", value: self.miniLabelTextStyle.rawValue)
        self.callback()
    }
}
