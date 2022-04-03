//
//  FPVViewController2.swift
//  DroneMLSwift
//
//  Created by Fahim Hasan Khan on 4/3/22.
//  Copyright © 2022 DJI. All rights reserved.
//

//
//  FPVViewController.swift
//  iOS-FPVDemo-Swift
//

import UIKit
import DJISDK
import DJIWidget

class FPVViewController2: UIViewController,  DJIVideoFeedListener, DJISDKManagerDelegate, DJICameraDelegate, DJIVideoPreviewerFrameControlDelegate {
    
    var isRecording : Bool!
    var isMLrunning : Bool = false
    var isDetected : Bool = false
    
    var sample = 0
    
    var temppixelbuffer: CVPixelBuffer!
    
    let enableBridgeMode = false
    
    let bridgeAppIP = "10.81.52.50"
    

    @IBOutlet var runMLBUtton: UIButton!
    @IBOutlet var countLabel: UILabel!
    @IBOutlet var recordTimeLabel: UILabel!
    @IBOutlet var recordButton: UIButton!
    @IBOutlet var fpvView: PreviewView!
    @IBOutlet weak var overlayView: OverlayView!
    
    // MARK: Constants
    private let displayFont = UIFont.systemFont(ofSize: 14.0, weight: .medium)
    private let edgeOffset: CGFloat = 2.0
    private let labelOffset: CGFloat = 10.0

    var timer = Timer()
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

    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
//        let backgroundImage = UIImageView(frame: UIScreen.main.bounds)
//        backgroundImage.image = UIImage(named: "car.png")
//        backgroundImage.contentMode =  UIView.ContentMode.scaleToFill
//        self.fpvView.insertSubview(backgroundImage, at: 0)
//        self.imageML()
        fpvView.previewLayer.frame = view.bounds
    }
    
    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      fpvView.previewLayer.frame = view.bounds
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
        
        //self.showAlertViewWithTitle(title:"Register App", withMessage: message)
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
        //self.recordTimeLabel.text = String(count)
        
        if (self.isRecording == true) {
            self.recordButton.setTitle("Stop Recording", for: .normal)
            self.recordButton.setTitleColor(.systemGreen, for: .normal)
        } else {
            self.recordButton.setTitle("Start Recording", for: .normal)
            self.recordButton.setTitleColor(.systemRed, for: .normal)
        }
        
        //Fahim - stopping recording autometically after certain time
        if (formatSeconds(seconds: cameraState.currentVideoRecordingTimeInSeconds) == "00:15"){
            camera.stopRecordVideo(completion: { (error) in
                if let _ = error {
                    NSLog("Stop Record Video Error: " + String(describing: error))
                }
            })
        }

        //Update UISegmented Control's State
        
        //Fahim - setting video record mode as default
        camera.setMode(DJICameraMode.recordVideo,  withCompletion: { (error) in
            if let _ = error {
                NSLog("Set RecordVideo Mode Error: " + String(describing: error))
            }
        })
        
        //let img = self.fpvView.asImage()
        
        //let renderer = UIGraphicsImageRenderer(size: fpvView.bounds.size)
        //let img = renderer.image { ctx in fpvView.drawHierarchy(in: fpvView.bounds, afterScreenUpdates: true) }
        //self.imageView.image = img
        
        if (self.isMLrunning == true){
            //self.timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true, block: { _ in self.imageML()})
            if (sample % 10 == 0){
                self.imageML()
            }
            self.runMLBUtton.setTitle("Stop ML", for: .normal)
            self.runMLBUtton.setTitleColor(.systemGreen, for: .normal)
            //self.isMLrunning = false
        } else{
            self.runMLBUtton.setTitle("Run ML", for: .normal)
            self.runMLBUtton.setTitleColor(.systemRed, for: .normal)
        }
        sample = sample + 1
        //self.imageML()
        //self.timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true, block: { _ in self.imageML()})
    }
    
    // MARK: DJIVideoFeedListener Method
    func videoFeed(_ videoFeed: DJIVideoFeed, didUpdateVideoData rawData: Data) {
        self.temppixelbuffer = fromData(rawData, width: 1280, height: 720, pixelFormat: kCVPixelFormatType_32ARGB)
        
        let videoData = rawData as NSData
        let videoBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: videoData.length)
        videoData.getBytes(videoBuffer, length: videoData.length)
        DJIVideoPreviewer.instance().push(videoBuffer, length: Int32(videoData.length))
    }
    
    func fromData(_ data: Data, width: Int, height: Int, pixelFormat: OSType) -> CVPixelBuffer {
        data.withUnsafeBytes { buffer in
            var pixelBuffer: CVPixelBuffer!

            let result = CVPixelBufferCreate(kCFAllocatorDefault, width, height, pixelFormat, nil, &pixelBuffer)
            guard result == kCVReturnSuccess else { fatalError() }

            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

            var source = buffer.baseAddress!

            for plane in 0 ..< CVPixelBufferGetPlaneCount(pixelBuffer) {
                let dest      = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane)
                let height      = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
                let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, plane)
                let planeSize = height * bytesPerRow

                memcpy(dest, source, planeSize)
                source += planeSize
            }

            return pixelBuffer
        }
    }
    
    func imageML(){
        //convert PreviewView to UIImage
        //let image =  UIImage.init(view: fpvView)
        //let img = self.fpvView.asImage()
        //let img2 = UIImage(named:"car.png")
        let renderer = UIGraphicsImageRenderer(size: fpvView.bounds.size)
        let img = renderer.image { ctx in fpvView.drawHierarchy(in: fpvView.bounds, afterScreenUpdates: true) }
        
        //let img1 = self.resizeImage(image: img, targetSize: CGSize(width: 200.0, height: 200.0))
        //let img1 = img.resizeImageTo(size: CGSize(width: 300.0, height: 300.0))
        
        //self.imageView.image = img
        //self.imageView2.image = img1
        
        //convert UIImage to CVPixelBuffer

        let pixelbuffer: CVPixelBuffer? = buffer(from: img)
        //let pixelbuffer: CVPixelBuffer? = buffer(from: img2!)
        
        self.runModel(onPixelBuffer: pixelbuffer!)
        //self.runModel(onPixelBuffer: temppixelbuffer)
    }
    
    func buffer(from image: UIImage) -> CVPixelBuffer? {
      let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
      var pixelBuffer : CVPixelBuffer?
      let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(image.size.width), Int(image.size.height), kCVPixelFormatType_32ARGB, attrs, &pixelBuffer)
      guard (status == kCVReturnSuccess) else {
        return nil
      }

      CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
      let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)

      let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
      let context = CGContext(data: pixelData, width: Int(image.size.width), height: Int(image.size.height), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)

      context?.translateBy(x: 0, y: image.size.height)
      context?.scaleBy(x: 1.0, y: -1.0)

      UIGraphicsPushContext(context!)
      image.draw(in: CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height))
      UIGraphicsPopContext()
      CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))

      return pixelBuffer
    }
    
    /** This method runs the live camera pixelBuffer through tensorFlow to get the result.
     */
    @objc  func runModel(onPixelBuffer pixelBuffer: CVPixelBuffer) {

      // Run the live camera pixelBuffer through tensorFlow to get the result

      result = self.modelDataHandler?.runModel(onFrame: pixelBuffer)

      guard let displayResult = result else {
        return
      }
        //displayResult.inferences.count
      self.countLabel.text = "Count: " + String(displayResult.inferences.count)

      let width = CVPixelBufferGetWidth(pixelBuffer)
      let height = CVPixelBufferGetHeight(pixelBuffer)

      DispatchQueue.main.async {

        //Draws the bounding boxes and displays class names and confidence scores.
        self.drawAfterPerformingCalculations(onInferences: displayResult.inferences, withImageSize: CGSize(width: CGFloat(width), height: CGFloat(height)))
      }
    }
    
    /**
     This method takes the results, translates the bounding box rects to the current view, draws the bounding boxes, classNames and confidence scores of inferences.
     */
    func drawAfterPerformingCalculations(onInferences inferences: [Inference], withImageSize imageSize:CGSize) {

      self.overlayView.objectOverlays = []
      self.overlayView.setNeedsDisplay()
      //guard !inferences.isEmpty else {
        //return
      //}

      var objectOverlays: [ObjectOverlay] = []
      //let objectOverlayTest = ObjectOverlay(name: "Test", borderRect: CGRect(x: 100.0, y: 100.0, width: 200.0, height: 200.0), nameStringSize: CGSize(width: 90.0, height: 15.0), color: UIColor.red, font: self.displayFont)
      //objectOverlays.append(objectOverlayTest)
      
      var count = 0
      for inference in inferences {

        // Translates bounding box rect to current view.
        var convertedRect = inference.rect.applying(CGAffineTransform(scaleX: self.overlayView.bounds.size.width / imageSize.width, y: self.overlayView.bounds.size.height / imageSize.height))

        if convertedRect.origin.x < 0 {
          convertedRect.origin.x = self.edgeOffset
        }

        if convertedRect.origin.y < 0 {
          convertedRect.origin.y = self.edgeOffset
        }

        if convertedRect.maxY > self.overlayView.bounds.maxY {
          convertedRect.size.height = self.overlayView.bounds.maxY - convertedRect.origin.y - self.edgeOffset
        }

        if convertedRect.maxX > self.overlayView.bounds.maxX {
          convertedRect.size.width = self.overlayView.bounds.maxX - convertedRect.origin.x - self.edgeOffset
        }

        let confidenceValue = Int(inference.confidence * 100.0)
        let string = "\(inference.className)  (\(confidenceValue)%)"

        let size = string.size(usingFont: self.displayFont)

        let objectOverlay = ObjectOverlay(name: string, borderRect: convertedRect, nameStringSize: size, color: inference.displayColor, font: self.displayFont)

        //if inference.className == "car" || inference.className == "person"{
        if inference.className == "person"{
            objectOverlays.append(objectOverlay)
            count = count + 1
        }
      }

      // Hands off drawing to the OverlayView
      self.draw(objectOverlays: objectOverlays)
      //self.countLabel.text = "Count: " + String(count)
    }

    /** Calls methods to update overlay view with detected bounding boxes and class names.
     */
    func draw(objectOverlays: [ObjectOverlay]) {
      self.overlayView.objectOverlays = objectOverlays
      self.overlayView.setNeedsDisplay()
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
    
    
    @IBAction func runMLAction(_ sender: UIButton) {
        if (self.isMLrunning == true){
            isMLrunning = false
        }
        else{
            isMLrunning = true
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
