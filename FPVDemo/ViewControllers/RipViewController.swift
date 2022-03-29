//
//  RipViewController.swift
//  DroneMLSwift
//
//  Created by Fahim Hasan Khan on 3/28/22.
//  Copyright © 2022 DJI. All rights reserved.
//

//
//  FPVViewController.swift
//  iOS-FPVDemo-Swift
//

import UIKit
import DJISDK
import DJIWidget

class RipViewController: UIViewController,  DJIVideoFeedListener, DJISDKManagerDelegate, DJICameraDelegate, DJIVideoPreviewerFrameControlDelegate {
    
    var isRecording : Bool!
    
    let enableBridgeMode = false
    
    let bridgeAppIP = "10.81.52.50"
    
    @IBOutlet var recordTimeLabel: UILabel!
    @IBOutlet var recordButton: UIButton!
    @IBOutlet var fpvView: PreviewView!
    @IBOutlet weak var overlayView: OverlayView!
    
    // MARK: Constants
    private let displayFont = UIFont.systemFont(ofSize: 14.0, weight: .medium)
    private let edgeOffset: CGFloat = 2.0
    private let labelOffset: CGFloat = 10.0

    // Holds the results at any time
    private var result: Result?
    // MARK: Controllers that manage functionality
    private var modelDataHandler: ModelDataHandler? =
      ModelDataHandler(modelFileInfo: MobileNetSSD.modelInfo, labelsFileInfo: MobileNetSSD.labelsInfo)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard modelDataHandler != nil else {
         fatalError("Failed to load model")
        }
        
        DJISDKManager.registerApp(with: self)
        recordTimeLabel.isHidden = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    
        if let camera = fetchCamera(), let delegate = camera.delegate, delegate.isEqual(self) {
            camera.delegate = nil
        }
        
        self.resetVideoPreview()
    }
    
    func setupVideoPreviewer() {
        DJIVideoPreviewer.instance().setView(self.fpvView)
        DJISDKManager.videoFeeder()?.primaryVideoFeed.add(self, with: nil)
        DJIVideoPreviewer.instance().start()
        DJIVideoPreviewer.instance()?.frameControlHandler = self;
    }
    
    func resetVideoPreview() {
        DJIVideoPreviewer.instance().unSetView()
        DJISDKManager.videoFeeder()?.primaryVideoFeed.remove(self)
    }
    
    func fetchCamera() -> DJICamera? {
        guard let product = DJISDKManager.product() else {
            return nil
        }
        if product is DJIAircraft {
            return (product as! DJIAircraft).camera
        }
        return nil
    }
    
    func formatSeconds(seconds: UInt) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "mm:ss"
        return(dateFormatter.string(from: date))
    }
    
    func showAlertViewWithTitle(title: String, withMessage message: String) {
        let alert = UIAlertController.init(title: title, message: message, preferredStyle: .alert)
        let okAction = UIAlertAction.init(title:"OK", style: .default, handler: nil)
        alert.addAction(okAction)
        self.present(alert, animated: true, completion: nil)
    }
    
    // MARK: DJISDKManagerDelegate Methods
    func productConnected(_ product: DJIBaseProduct?) {
        
        NSLog("Product Connected")
        
        if let camera = fetchCamera() {
            camera.delegate = self
        }
        self.setupVideoPreviewer()
        
        //If this demo is used in China, it's required to login to your DJI account to activate the application. Also you need to use DJI Go app to bind the aircraft to your DJI account. For more details, please check this demo's tutorial.
        DJISDKManager.userAccountManager().logIntoDJIUserAccount(withAuthorizationRequired: false) { (state, error) in
            if let _ = error {
                NSLog("Login failed: %@" + String(describing: error))
            }
        }
    }
    
    func productDisconnected() {
        NSLog("Product Disconnected")

        if let camera = fetchCamera(), let delegate = camera.delegate, delegate.isEqual(self) {
            camera.delegate = nil
        }
        self.resetVideoPreview()
    }
    
    func appRegisteredWithError(_ error: Error?) {
        var message = "Register App Successed!"
        if let _ = error {
            message = "Register app failed! Please enter your app key and check the network."
        } else {
            if enableBridgeMode {
                DJISDKManager.enableBridgeMode(withBridgeAppIP: bridgeAppIP)
            } else {
                DJISDKManager.startConnectionToProduct()
            }
        }
        
        self.showAlertViewWithTitle(title:"Register App", withMessage: message)
    }
    
    func didUpdateDatabaseDownloadProgress(_ progress: Progress) {
        NSLog("Download database : \n%lld/%lld", progress.completedUnitCount, progress.totalUnitCount)
    }

    //Fahim: Camera functions start here
    
    
    // MARK: DJICameraDelegate Method
    func camera(_ camera: DJICamera, didUpdate cameraState: DJICameraSystemState) {
        self.isRecording = cameraState.isRecording
        self.recordTimeLabel.isHidden = !self.isRecording
        
        self.recordTimeLabel.text = formatSeconds(seconds: cameraState.currentVideoRecordingTimeInSeconds)
        
        if (self.isRecording == true) {
            self.recordButton.setTitle("Rip Detected!! Recording!", for: .normal)
            self.recordButton.setTitleColor(.systemGreen, for: .normal)
        } else {
            self.recordButton.setTitle("No Rip Detected!! Not Recording!", for: .normal)
            self.recordButton.setTitleColor(.systemRed, for: .normal)
        }
        
        //Update UISegmented Control's State
        camera.setMode(DJICameraMode.recordVideo,  withCompletion: { (error) in
            if let _ = error {
                NSLog("Set RecordVideo Mode Error: " + String(describing: error))
            }
        })
    }
    
    // MARK: DJIVideoFeedListener Method
    func videoFeed(_ videoFeed: DJIVideoFeed, didUpdateVideoData rawData: Data) {
        let videoData = rawData as NSData
        let videoBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: videoData.length)
        videoData.getBytes(videoBuffer, length: videoData.length)
        DJIVideoPreviewer.instance().push(videoBuffer, length: Int32(videoData.length))
    }
    
    
    @IBAction func recordAction(_ sender: UIButton) {
        guard let camera = fetchCamera() else {
            return
        }
        
        if (self.isRecording) {
            camera.stopRecordVideo(completion: { (error) in
                if let _ = error {
                    NSLog("Stop Record Video Error: " + String(describing: error))
                }
            })
        } else {
            camera.startRecordVideo(completion: { (error) in
                if let _ = error {
                    NSLog("Start Record Video Error: " + String(describing: error))
                }
            })
        }
    }
    
    
    // MARK: DJIVideoPreviewerFrameControlDelegate Method
    func parseDecodingAssistInfo(withBuffer buffer: UnsafeMutablePointer<UInt8>!, length: Int32, assistInfo: UnsafeMutablePointer<DJIDecodingAssistInfo>!) -> Bool {
        return DJISDKManager.videoFeeder()?.primaryVideoFeed.parseDecodingAssistInfo(withBuffer: buffer, length: length, assistInfo: assistInfo) ?? false
    }
    
    func isNeedFitFrameWidth() -> Bool {
        let displayName = fetchCamera()?.displayName
        if displayName == DJICameraDisplayNameMavic2ZoomCamera ||
            displayName == DJICameraDisplayNameMavic2ProCamera {
            return true
        }
        return false
    }
    
    func syncDecoderStatus(_ isNormal: Bool) {
        DJISDKManager.videoFeeder()?.primaryVideoFeed.syncDecoderStatus(isNormal)
    }
    
    func decodingDidSucceed(withTimestamp timestamp: UInt32) {
        DJISDKManager.videoFeeder()?.primaryVideoFeed.decodingDidSucceed(withTimestamp: UInt(timestamp))
    }
    
    func decodingDidFail() {
        DJISDKManager.videoFeeder()?.primaryVideoFeed.decodingDidFail()
    }
    
}
