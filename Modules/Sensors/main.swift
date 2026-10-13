//
//  main.swift
//  Sensors
//
//  Created by Serhiy Mytrovtsiy on 17/06/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

public class Sensors: Module {
    private var sensorsReader: SensorsReader?
    private let popupView: Popup
    private let settingsView: Settings
    private let portalView: Portal
    private let notificationsView: Notifications
    
    private enum MiniLabelMode: String {
        case valueOnly = "valueOnly"
        case labelAndValue = "labelAndValue"
    }
    
    private var fanValueState: FanValue {
        FanValue(rawValue: Store.shared.string(key: "\(self.config.name)_fanValue", defaultValue: "percentage")) ?? .percentage
    }
    
    private var selectedSensor: String
    
    private var miniLabelMode: MiniLabelMode {
        MiniLabelMode(rawValue: Store.shared.string(key: "\(self.config.name)_miniLabelMode", defaultValue: MiniLabelMode.labelAndValue.rawValue)) ?? .labelAndValue
    }
    
    private enum MiniLabelTextStyle: String {
        case sensorName = "sensorName"
        case shortLetters = "shortLetters"
        case firstLetter = "firstLetter"
    }
    
    private var miniLabelTextStyle: MiniLabelTextStyle {
        MiniLabelTextStyle(rawValue: Store.shared.string(key: "\(self.config.name)_miniLabelTextStyle", defaultValue: MiniLabelTextStyle.sensorName.rawValue)) ?? .sensorName
    }
    
    private func firstLetter(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return String(trimmed.prefix(1))
    }
    
    public init() {
        self.settingsView = Settings(.sensors)
        self.popupView = Popup()
        self.portalView = Portal(.sensors)
        self.notificationsView = Notifications(.sensors)
        self.selectedSensor = Store.shared.string(key: "\(ModuleType.sensors.stringValue)_sensor", defaultValue: "Average System Total")
        
        super.init(
            moduleType: .sensors,
            popup: self.popupView,
            settings: self.settingsView,
            portal: self.portalView,
            notifications: self.notificationsView
        )
        guard self.available else { return }
        
        self.sensorsReader = SensorsReader { [weak self] value in
            self?.usageCallback(value)
        }
        
        self.settingsView.setList(self.sensorsReader?.list.sensors)
        self.popupView.setup(self.sensorsReader?.list.sensors)
        self.portalView.setup(self.sensorsReader?.list.sensors)
        self.notificationsView.setup(self.sensorsReader?.list.sensors)
        
        self.settingsView.callback = { [weak self] in
            self?.sensorsReader?.read()
        }
        self.settingsView.setInterval = { [weak self] value in
            self?.sensorsReader?.setInterval(value)
        }
        self.settingsView.HIDcallback = { [weak self] in
            DispatchQueue.global(qos: .background).async {
                self?.sensorsReader?.HIDCallback()
                DispatchQueue.main.async {
                    self?.popupView.setup(self?.sensorsReader?.list.sensors)
                    self?.portalView.setup(self?.sensorsReader?.list.sensors)
                    self?.settingsView.setList(self?.sensorsReader?.list.sensors)
                    self?.notificationsView.setup(self?.sensorsReader?.list.sensors)
                }
            }
        }
        self.settingsView.unknownCallback = { [weak self] in
            DispatchQueue.global(qos: .background).async {
                self?.sensorsReader?.unknownCallback()
                DispatchQueue.main.async {
                    self?.popupView.setup(self?.sensorsReader?.list.sensors)
                    self?.portalView.setup(self?.sensorsReader?.list.sensors)
                    self?.settingsView.setList(self?.sensorsReader?.list.sensors)
                    self?.notificationsView.setup(self?.sensorsReader?.list.sensors)
                }
            }
        }
        self.selectedSensor = Store.shared.string(key: "\(ModuleType.sensors.stringValue)_sensor", defaultValue: self.selectedSensor)
        self.settingsView.selectedHandler = { [weak self] value in
            self?.selectedSensor = value
            self?.sensorsReader?.read()
        }
        
        self.setReaders([self.sensorsReader])
    }
    
    public override func willTerminate() {
        guard SMCHelper.shared.isActive(), let reader = self.sensorsReader else { return }
        
        reader.list.sensors.filter({ $0 is Fan }).forEach { (s: Sensor_p) in
            if let f = s as? Fan, let mode = f.customMode {
                if !mode.isAutomatic {
                    SMCHelper.shared.setFanMode(f.id, mode: FanMode.automatic.rawValue)
                }
            }
        }
    }
    
    private func usageCallback(_ raw: Sensors_List?) {
        guard let value = raw, self.enabled else { return }
        
        self.popupView.usageCallback(value.sensors)
        self.portalView.usageCallback(value.sensors)
        self.notificationsView.usageCallback(value.sensors)
        
        let activeWidgets = self.menuBar.widgets.filter{ $0.isActive }
        self.sensorsReader?.sleepMode(state: activeWidgets.contains(where: {$0.item is Label}) && activeWidgets.count == 1)
        
        activeWidgets.forEach { (w: SWidget) in
            switch w.item {
            case let widget as Mini:
                if let active = value.sensors.first(where: { $0.key == self.selectedSensor }) {
                    var value: Double = active.localValue/100
                    var unit: String = active.miniUnit
                    if let fan = active as? Fan, self.fanValueState == .percentage {
                        value = Double(fan.percentage)/100
                        unit = "%"
                    }
                    if value > 999 {
                        unit = ""
                    }
                    
                    let showLabel = self.miniLabelMode == .labelAndValue
                    widget.setLabelState(showLabel)
                    if showLabel {
                        switch self.miniLabelTextStyle {
                        case .sensorName:
                            widget.setTitle("\(localizedString(active.name)):")
                        case .shortLetters:
                            widget.setTitle("A:")
                        case .firstLetter:
                            widget.setTitle("\(self.firstLetter(localizedString(active.name))):")
                        }
                    }
                    widget.setValue(value)
                    widget.setSuffix(unit)
                }
            case let widget as StackWidget:
                var list: [Stack_t] = []
                var letterIndex: Int = 0
                
                value.sensors.forEach { (s: Sensor_p) in
                    if s.state {
                        var value = s.formattedMiniValue
                        if let f = s as? Fan {
                            if self.fanValueState == .percentage {
                                value = "\(f.percentage)%"
                            }
                        }
                        
                        if self.miniLabelMode == .labelAndValue {
                            let label: String
                            switch self.miniLabelTextStyle {
                            case .sensorName:
                                label = localizedString(s.name)
                            case .shortLetters:
                                let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
                                label = letterIndex < letters.count ? String(letters[letterIndex]) : "\(letterIndex+1)"
                            case .firstLetter:
                                label = self.firstLetter(localizedString(s.name))
                            }
                            letterIndex += 1
                            list.append(Stack_t(key: s.key, value: "\(label): \(value)"))
                        } else {
                            list.append(Stack_t(key: s.key, value: value))
                        }
                    }
                }
                
                widget.setValues(list)
            case let widget as BarChart:
                var flatList: [[ColorValue]] = []
                value.sensors.filter{ $0 is Fan }.forEach { (s: Sensor_p) in
                    if s.state, let f = s as? Fan {
                        flatList.append([ColorValue(Double(f.percentage) / 100)])
                    }
                }
                widget.setValue(flatList)
            case let widget as IconWidget:
                widget.setValue(value.sensors.contains(where: { $0 is Fan && !$0.isComputed && $0.value > 0 }))
            default: break
            }
        }
    }
}
