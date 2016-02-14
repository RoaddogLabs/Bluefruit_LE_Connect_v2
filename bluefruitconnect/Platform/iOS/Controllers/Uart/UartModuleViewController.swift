//
//  UartModuleViewController.swift
//  Bluefruit Connect
//
//  Created by Antonio García on 06/02/16.
//  Copyright © 2016 Adafruit. All rights reserved.
//

import UIKit
import UIColor_Hex

class UartModuleViewController: ModuleViewController {

    // UI
    @IBOutlet weak var baseTableView: UITableView!
    @IBOutlet weak var baseTextView: UITextView!
    @IBOutlet weak var statsLabel: UILabel!
    @IBOutlet weak var statsLabeliPadLeadingConstraint: NSLayoutConstraint!         // remove ipad or iphone depending on the platform
    @IBOutlet weak var statsLabeliPhoneLeadingConstraint: NSLayoutConstraint!       // remove ipad or iphone depending on the platform

    @IBOutlet weak var inputTextField: UITextField!
    @IBOutlet weak var sendInputButton: UIButton!
    @IBOutlet weak var keyboardSpacerHeightConstraint: NSLayoutConstraint!
    
    private var mqttBarButtonItem: UIBarButtonItem!
    private var mqttBarButtonItemImageView : UIImageView?
    @IBOutlet weak var moreOptionsNavigationItem: UIBarButtonItem!
    @IBOutlet weak var mainStackView: UIStackView!
    @IBOutlet weak var controlsView: UIView!
    @IBOutlet weak var inputControlsStackView: UIStackView!
    
    @IBOutlet weak var showEolSwitch: UISwitch!
    @IBOutlet weak var addEolSwitch: UISwitch!
    @IBOutlet weak var clearButton: UIButton!
    @IBOutlet weak var displayModeSegmentedControl: UISegmentedControl!
    @IBOutlet weak var dataModeSegmentedControl: UISegmentedControl!
    
    // Data
    private let uartData = UartModuleManager()
    private var txColor = Preferences.uartSentDataColor
    private var rxColor = Preferences.uartReceveivedDataColor
    private let timestampDateFormatter = NSDateFormatter()
    private var tableCachedDataBuffer : [UartDataChunk]?
    private var textCachedBuffer = NSMutableAttributedString()
    
    private let keyboardPositionNotifier = KeyboardPositionNotifier()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Peripheral should be connected
        uartData.delegate = self
        uartData.blePeripheral = BleManager.sharedInstance.blePeripheralConnected       // Note: this will start the service discovery
        guard uartData.blePeripheral != nil else {
            DLog("Error: Uart: blePeripheral is nil")
            return
        }
        
        // Title
        let localizationManager = LocalizationManager.sharedInstance
        let title = String(format: localizationManager.localizedString("uart_navigation_title_format"), arguments: [uartData.blePeripheral!.name])
        tabBarController?.navigationItem.title = title
        
        // Init Data
        keyboardPositionNotifier.delegate = self
        timestampDateFormatter.setLocalizedDateFormatFromTemplate("HH:mm:ss")
        
        // Setup tableView
        baseTableView.estimatedRowHeight = 44
        baseTableView.rowHeight = UITableViewAutomaticDimension
        baseTableView.layer.borderWidth = 1
        baseTableView.layer.borderColor = UIColor.lightGrayColor().CGColor

        // Setup textview
        baseTextView.layer.borderWidth = 1
        baseTextView.layer.borderColor = UIColor.lightGrayColor().CGColor
        
        // Setup controls
        displayModeSegmentedControl.setTitle(localizationManager.localizedString("uart_settings_displayMode_timestamp"), forSegmentAtIndex: 0)
        displayModeSegmentedControl.setTitle(localizationManager.localizedString("uart_settings_displayMode_text"), forSegmentAtIndex: 1)
        dataModeSegmentedControl.setTitle(localizationManager.localizedString("uart_settings_dataMode_ascii"), forSegmentAtIndex: 0)
        dataModeSegmentedControl.setTitle(localizationManager.localizedString("uart_settings_dataMode_hex"), forSegmentAtIndex: 1)
        
        // Init options layout
        if traitCollection.userInterfaceIdiom == .Pad {            // iPad
            // moreOptionsNavigationItem.enabled = false
            
            self.view.removeConstraint(statsLabeliPhoneLeadingConstraint)
            
            // Resize input UISwitch controls
            for subStackView in inputControlsStackView.subviews {
                for subview in subStackView.subviews {
                    if let switchView = subview as? UISwitch {
                        switchView.transform = CGAffineTransformMakeScale(0.6, 0.6)
                    }
                }
            }
        }
        else {            // iPhone
            self.view.removeConstraint(statsLabeliPadLeadingConstraint)
            statsLabel.textAlignment = .Left
            
            inputControlsStackView.hidden = true
        }
        
        // Mqtt init
        mqttBarButtonItemImageView = UIImageView(image: UIImage(named: "mqtt_disconnected")!.tintWithColor(self.view.tintColor))      // use a uiimageview as custom barbuttonitem to allow frame animations
        mqttBarButtonItemImageView!.tintColor = self.view.tintColor
        mqttBarButtonItemImageView?.addGestureRecognizer(UITapGestureRecognizer(target: self, action: "onClickMqtt"))
        
        let mqttManager = MqttManager.sharedInstance
        if (MqttSettings.sharedInstance.isConnected) {
            mqttManager.delegate = uartData
            mqttManager.connectFromSavedSettings()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // Hide top controls on iPhone
         if traitCollection.userInterfaceIdiom == .Phone {
            controlsView.hidden = true
        }
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        registerNotifications(true)

        uartData.dataBufferEnabled = true
        
        // Remove "more options" navigation bar button on iPad
        if traitCollection.userInterfaceIdiom == .Pad {
            // Remove more item
            tabBarController!.navigationItem.rightBarButtonItems! = []

            // Add mqtt bar item
            mqttBarButtonItem = UIBarButtonItem(customView: mqttBarButtonItemImageView!)
            tabBarController!.navigationItem.rightBarButtonItems!.append(mqttBarButtonItem)
        }
        else {
            // Add mqtt bar item
            mqttBarButtonItem = UIBarButtonItem(customView: mqttBarButtonItemImageView!)
            tabBarController!.navigationItem.rightBarButtonItems!.append(mqttBarButtonItem)
        }
        
        // Add mqtt bar item
        if tabBarController!.navigationItem.rightBarButtonItems!.count == 0 {
        }
        
        // UI
        reloadDataUI()
        showEolSwitch.on = Preferences.uartIsAutomaticEolEnabled
        addEolSwitch.on = Preferences.uartIsEchoEnabled
        displayModeSegmentedControl.selectedSegmentIndex = Preferences.uartIsDisplayModeTimestamp ? 0:1
        dataModeSegmentedControl.selectedSegmentIndex = Preferences.uartIsInHexMode ? 1:0

        // Check if characteristics are ready
        let isUartReady = uartData.isReady()
        inputTextField.enabled = isUartReady
        inputTextField.backgroundColor = isUartReady ? UIColor.whiteColor() : UIColor.blackColor().colorWithAlphaComponent(0.1)
        
        // MQTT
        let mqttManager = MqttManager.sharedInstance
        if (MqttSettings.sharedInstance.isConnected) {
            mqttManager.delegate = uartData
        }
        mqttUpdateStatusUI()
    }
    
    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated)
        
        if !Config.uartShowAllUartCommunication {
            uartData.dataBufferEnabled = false
        }
        registerNotifications(false)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    deinit {
        let mqttManager = MqttManager.sharedInstance
        mqttManager.disconnect()
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == "uartSettingsSegue"  {
            if let controller = segue.destinationViewController.popoverPresentationController {
                controller.delegate = self
                
                let uartSettingsViewController = segue.destinationViewController as! UartSettingsViewController
                uartSettingsViewController.onClickClear = {
                    self.onClickClear(self)
                }
                uartSettingsViewController.onClickExport = {
                    self.onClickExport(self)
                }
            }
        }
    }
    
    // MARK: - Preferences
    func registerNotifications(register : Bool) {
        
        let notificationCenter =  NSNotificationCenter.defaultCenter()
        if (register) {
            notificationCenter.addObserver(self, selector: "preferencesUpdated:", name: Preferences.PreferencesNotifications.DidUpdatePreferences.rawValue, object: nil)
        }
        else {
            notificationCenter.removeObserver(self, name: Preferences.PreferencesNotifications.DidUpdatePreferences.rawValue, object: nil)
        }
    }
    
    func preferencesUpdated(notification : NSNotification) {
        txColor = Preferences.uartSentDataColor
        rxColor = Preferences.uartReceveivedDataColor
        reloadDataUI()
    }
    
    // MARK: - UI Updates
    func reloadDataUI() {
        let displayMode = Preferences.uartIsDisplayModeTimestamp ? UartModuleManager.DisplayMode.Table : UartModuleManager.DisplayMode.Text
        
        baseTableView.hidden = displayMode == .Text
        baseTextView.hidden = displayMode == .Table
        
        switch(displayMode) {
        case .Text:
            
            textCachedBuffer.setAttributedString(NSAttributedString())
            for dataChunk in uartData.dataBuffer {
                addChunkToUIText(dataChunk)
            }
            baseTextView.attributedText = textCachedBuffer

            baseTextView.attributedText = textCachedBuffer
            /*
            baseTextView.attributedText.
            
            if let textStorage = self.baseTextView.textStorage {
                
                let isScrollAtTheBottom = baseTextView.enclosingScrollView?.verticalScroller?.floatValue == 1
                
                textStorage.beginEditing()
                textStorage.replaceCharactersInRange(NSMakeRange(0, textStorage.length), withAttributedString: NSAttributedString())        // Clear text
                for dataChunk in uartData.dataBuffer {
                    addChunkToUIText(dataChunk)
                }
                textStorage .endEditing()
                if isScrollAtTheBottom {
                    baseTextView.scrollRangeToVisible(NSMakeRange(textStorage.length, 0))
                }
                
            }
            */
            
        case .Table:
        
            baseTableView.reloadData()
        /*
            //let isScrollAtTheBottom = tableCachedDataBuffer == nil || tableCachedDataBuffer!.isEmpty  || baseTableView.enclosingScrollView?.verticalScroller?.floatValue == 1
            let isScrollAtTheBottom = tableCachedDataBuffer == nil || tableCachedDataBuffer!.isEmpty || NSLocationInRange(tableCachedDataBuffer!.count-1, baseTableView.rowsInRect(baseTableView.visibleRect))
            
            baseTableView.sizeLastColumnToFit()
            baseTableView.reloadData()
            if isScrollAtTheBottom {
                baseTableView.scrollToEndOfDocument(nil)
            }
*/
        }
        
        updateBytesUI()
    }

    func updateBytesUI() {
        if let blePeripheral = uartData.blePeripheral {
            let localizationManager = LocalizationManager.sharedInstance
            let sentBytesMessage = String(format: localizationManager.localizedString("uart_sentbytes_format"), arguments: [blePeripheral.uartData.sentBytes])
            let receivedBytesMessage = String(format: localizationManager.localizedString("uart_recievedbytes_format"), arguments: [blePeripheral.uartData.receivedBytes])
            
            statsLabel.text = String(format: "%@     %@", arguments: [sentBytesMessage, receivedBytesMessage])
        }
    }
    
    // MARK: - UI Actions
    func onClickMqtt() {
        let viewController = storyboard!.instantiateViewControllerWithIdentifier("UartMqttSettingsViewController")
        viewController.modalPresentationStyle = .Popover
        if let popovoverController = viewController.popoverPresentationController
        {
            popovoverController.sourceView = mqttBarButtonItemImageView
            popovoverController.delegate = self
        }
        presentViewController(viewController, animated: true, completion: nil)
    }
    
    @IBAction func onClickSend(sender: AnyObject) {
        let text = inputTextField.text != nil ? inputTextField.text! : ""
        
        var newText = text
        // Eol
        if (Preferences.uartIsAutomaticEolEnabled)  {
            newText += "\n"
        }
        
        uartData.sendMessageToUart(newText)
        inputTextField.text = ""
    }
    
    @IBAction func onInputTextFieldEdidtingDidEndOnExit(sender: UITextField) {
        onClickSend(sender)
    }
    
    @IBAction func onClickClear(sender: AnyObject) {
        uartData.clearData()
        reloadDataUI()
    }
    
    @IBAction func onClickExport(sender: AnyObject) {
        let dataBuffer = self.uartData.dataBuffer
        guard dataBuffer.count>0 else {
            showDialogWarningNoTextToExport()
            return;
        }
        
        let localizationManager = LocalizationManager.sharedInstance
        let alertController = UIAlertController(title: "Export data", message: "Choose the prefered format:", preferredStyle: .ActionSheet)
        
        for exportFormat in uartData.exportFormats {
            let exportAction = UIAlertAction(title: exportFormat.rawValue, style: .Default) {[unowned self] (_) in
                var text : String?
                
                switch(exportFormat) {
                case .txt:
                    text = UartDataExport.dataAsText(dataBuffer)
                case .csv:
                    text = UartDataExport.dataAsCsv(dataBuffer)
                case .json:
                    text = UartDataExport.dataAsJson(dataBuffer)
                    break
                case .xml:
                    //text = UartDataExport.dataAsXml(dataBuffer)
                    break
                }
                self.exportString(text)
                
            }
            alertController.addAction(exportAction)
        }
        
        let cancelAction = UIAlertAction(title: localizationManager.localizedString("dialog_cancel"), style: .Cancel, handler:nil)
        alertController.addAction(cancelAction)
        
        alertController.popoverPresentationController?.sourceView = clearButton
        self.presentViewController(alertController, animated: true, completion: nil)
    }
    
    private func exportString(text: String?) {
        if let text = text {
            let activityViewController = UIActivityViewController(activityItems: [text], applicationActivities: nil)
            activityViewController.popoverPresentationController?.sourceView = clearButton
            tabBarController?.navigationController?.presentViewController(activityViewController, animated: true, completion: nil)
        }
        else {
            DLog("exportString with empty text")
            showDialogWarningNoTextToExport()
        }
    }
    
    private func showDialogWarningNoTextToExport() {
        let localizationManager = LocalizationManager.sharedInstance
        let alertController = UIAlertController(title: nil, message: localizationManager.localizedString("uart_export_nodata"), preferredStyle: .Alert)
        let okAction = UIAlertAction(title: localizationManager.localizedString("dialog_ok"), style: .Default, handler:nil)
        alertController.addAction(okAction)
        self.presentViewController(alertController, animated: true, completion: nil)
        
    }
    
    @IBAction func onShowEchoValueChanged(sender: UISwitch) {
        Preferences.uartIsEchoEnabled = sender.on
    }
    
    @IBAction func onAddEolValueChanged(sender: UISwitch) {
        Preferences.uartIsAutomaticEolEnabled = sender.on
    }
    
    @IBAction func onDisplayModeChanged(sender: UISegmentedControl) {
         Preferences.uartIsDisplayModeTimestamp = sender.selectedSegmentIndex == 0
        
    }
    
    @IBAction func onDataModeChanged(sender: UISegmentedControl) {
         Preferences.uartIsInHexMode = sender.selectedSegmentIndex == 1
    }
    
}

// MARK: - UITableViewDataSource
extension UartModuleViewController : UITableViewDataSource {
    private static var dataFont = Font.systemFontOfSize(Font.systemFontSize())
    
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if (Preferences.uartIsEchoEnabled)  {
            tableCachedDataBuffer = uartData.dataBuffer
        }
        else {
            tableCachedDataBuffer = uartData.dataBuffer.filter({ (dataChunk : UartDataChunk) -> Bool in
                dataChunk.mode == .RX
            })
        }
        
        return tableCachedDataBuffer!.count
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        
        let reuseIdentifier = "TimestampCell"
        let cell = tableView.dequeueReusableCellWithIdentifier(reuseIdentifier, forIndexPath:indexPath)
        
        // Data binding in cellForRowAtIndexPath to avoid problems with multiple-line labels and dyanmic tableview height calculation
        let dataChunk = tableCachedDataBuffer![indexPath.row]
        let date = NSDate(timeIntervalSinceReferenceDate: dataChunk.timestamp)
        let dateString = timestampDateFormatter.stringFromDate(date)
        let modeString = LocalizationManager.sharedInstance.localizedString(dataChunk.mode == .RX ? "uart_timestamp_direction_rx" : "uart_timestamp_direction_tx")
        let color = dataChunk.mode == .TX ? txColor : rxColor
        
        let timestampCell = cell as! UartTimetampTableViewCell

        timestampCell.timeStampLabel.text = String(format: "%@ %@", arguments: [dateString, modeString])
        
        if let attributedText = UartModuleManager.attributeTextFromData(dataChunk.data, useHexMode: Preferences.uartIsInHexMode, color: color, font: UartModuleViewController.dataFont) {
            timestampCell.dataLabel.attributedText = attributedText
        }
        else {
            timestampCell.dataLabel.attributedText = NSAttributedString(string: " ")        // space to maintain height
        }
 
        timestampCell.contentView.backgroundColor = indexPath.row%2 == 0 ? UIColor.whiteColor() : UIColor(hex: 0xeeeeee)
        return cell
    }
}

// MARK: UITableViewDelegate
extension UartModuleViewController: UITableViewDelegate {
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        
    }
}

// MARK: - UartModuleDelegate
extension UartModuleViewController: UartModuleDelegate {
    
    func addChunkToUI(dataChunk : UartDataChunk) {
        // Check that the view has been initialized before updating UI
        guard baseTableView != nil else {
            return;
        }
        
        let displayMode = Preferences.uartIsDisplayModeTimestamp ? UartModuleManager.DisplayMode.Table : UartModuleManager.DisplayMode.Text

        switch(displayMode) {
        case .Text:
            addChunkToUIText(dataChunk)
            baseTextView.attributedText = textCachedBuffer
            
            let isScrollAtBottom = true     // Todo: calculate better if the user moved the scroll
            if isScrollAtBottom {
                /*
                view.layoutIfNeeded()
                baseTextView.scrollRectToVisible(CGRectMake(0, baseTextView.contentSize.height - baseTextView.bounds.size.height, baseTextView.bounds.size.width, baseTextView.bounds.size.height), animated: true)
*/
                
                /*
                let textLength = baseTextView.text.lengthOfBytesUsingEncoding(NSUTF8StringEncoding)
                if textLength > 0 {
                    let range = NSMakeRange(textLength - 1, 1);
                    baseTextView.scrollRangeToVisible(range);
                 
                }
*/
            }
            /*
            if let textStorage = self.baseTextView.textStorage {
                let isScrollAtTheBottom = baseTextView.enclosingScrollView?.verticalScroller?.floatValue == 1
                
                addChunkToUIText(dataChunk)
                
                if isScrollAtTheBottom {
                    // if scroll was at the bottom then autoscroll to the new bottom
                    baseTextView.scrollRangeToVisible(NSMakeRange(textStorage.length, 0))
                }
            }
*/

        case .Table:
            
            baseTableView.reloadData()
            
            let isScrollAtBottom = true     // Todo: calculate better if the user moved the scroll
            if isScrollAtBottom {
                view.layoutIfNeeded()
                baseTableView.scrollRectToVisible(CGRectMake(0, baseTableView.contentSize.height - baseTableView.bounds.size.height, baseTableView.bounds.size.width, baseTableView.bounds.size.height), animated: true)
            }
            
            /*
            let isScrollAtTheBottom = tableCachedDataBuffer == nil || tableCachedDataBuffer!.isEmpty || NSLocationInRange(tableCachedDataBuffer!.count-1, baseTableView.rowsInRect(baseTableView.visibleRect))
            //let isScrollAtTheBottom = tableCachedDataBuffer == nil || tableCachedDataBuffer!.isEmpty  || baseTableView.enclosingScrollView?.verticalScroller?.floatValue == 1
            
            baseTableView.reloadData()
            if isScrollAtTheBottom {
                // if scroll was at the bottom then autoscroll to the new bottom
                baseTableView.scrollToEndOfDocument(nil)
            }
*/
        }

        updateBytesUI()
    }
    
    private func addChunkToUIText(dataChunk : UartDataChunk) {
        
        if (Preferences.uartIsEchoEnabled || dataChunk.mode == .RX) {
            let color = dataChunk.mode == .TX ? txColor : rxColor
            
            if let attributedString = UartModuleManager.attributeTextFromData(dataChunk.data, useHexMode: Preferences.uartIsInHexMode, color: color, font: UartModuleViewController.dataFont) {
                textCachedBuffer.appendAttributedString(attributedString)
            }
        }
    }

    func mqttUpdateStatusUI() {
        if let imageView = mqttBarButtonItemImageView {
            let status = MqttManager.sharedInstance.status
            let tintColor = self.view.tintColor
            
            switch (status) {
            case .Connecting:
                let imageFrames = [
                    UIImage(named:"mqtt_connecting1")!.tintWithColor(tintColor),
                    UIImage(named:"mqtt_connecting2")!.tintWithColor(tintColor),
                    UIImage(named:"mqtt_connecting3")!.tintWithColor(tintColor)
                ]
                imageView.animationImages = imageFrames
                imageView.animationDuration = 0.5 * Double(imageFrames.count)
                imageView.animationRepeatCount = 0;
                imageView.startAnimating()
                
            case .Connected:
                imageView.stopAnimating()
                imageView.image = UIImage(named:"mqtt_connected")!.tintWithColor(tintColor)
                
            default:
                imageView.stopAnimating()
                imageView.image = UIImage(named:"mqtt_disconnected")!.tintWithColor(tintColor)
            }
        }
    }

    func mqttError(message: String, isConnectionError: Bool) {
        let localizationManager = LocalizationManager.sharedInstance

        let alertMessage = isConnectionError ? localizationManager.localizedString("uart_mqtt_connectionerror_title"): message
        let alertController = UIAlertController(title: nil, message: alertMessage, preferredStyle: .Alert)
        
        let okAction = UIAlertAction(title: localizationManager.localizedString("dialog_ok"), style: .Default, handler:nil)
        alertController.addAction(okAction)
        self.presentViewController(alertController, animated: true, completion: nil)
    }
}

// MARK: - CBPeripheralDelegate
extension UartModuleViewController: CBPeripheralDelegate {
    // Pass peripheral callbacks to UartData
    
    func peripheral(peripheral: CBPeripheral, didDiscoverServices error: NSError?) {
        uartData.peripheral(peripheral, didDiscoverServices:error)
    }
    
    func peripheral(peripheral: CBPeripheral, didDiscoverCharacteristicsForService service: CBService, error: NSError?) {
        
        uartData.peripheral(peripheral, didDiscoverCharacteristicsForService: service, error: error)
        
        // Check if ready
        if uartData.isReady() {
            // Enable input
            dispatch_async(dispatch_get_main_queue(), { [unowned self] in
                if self.inputTextField != nil {     // could be nil if the viewdidload has not been executed yet
                    self.inputTextField.enabled = true
                    self.inputTextField.backgroundColor = UIColor.whiteColor()
                }
                });
        }
    }
    
    func peripheral(peripheral: CBPeripheral, didUpdateValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
        uartData.peripheral(peripheral, didUpdateValueForCharacteristic: characteristic, error: error)
    }
}

// MARK: - KeyboardPositionNotifierDelegate
extension UartModuleViewController: KeyboardPositionNotifierDelegate {
    
    func onKeyboardPositionChanged(keyboardFrame : CGRect, keyboardShown : Bool) {
        var spacerHeight = keyboardFrame.height
        if let tabBarHeight = self.tabBarController?.tabBar.bounds.size.height {
            spacerHeight -= tabBarHeight
        }
        keyboardSpacerHeightConstraint.constant = max(spacerHeight, 0)

    }
}

// MARK: - UIPopoverPresentationControllerDelegate
extension UartModuleViewController : UIPopoverPresentationControllerDelegate {
    
    func adaptivePresentationStyleForPresentationController(PC: UIPresentationController) -> UIModalPresentationStyle {
        // This *forces* a popover to be displayed on the iPhone
        return .None
    }
    
    func popoverPresentationControllerDidDismissPopover(popoverPresentationController: UIPopoverPresentationController) {

        // MQTT
        let mqttManager = MqttManager.sharedInstance
        if (MqttSettings.sharedInstance.isConnected) {
            mqttManager.delegate = uartData
        }
        mqttUpdateStatusUI()
    }
}