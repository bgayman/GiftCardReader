//
//  ViewController.swift
//  GiftCardReader
//
//  Created by B Gay on 10/28/19.
//  Copyright © 2019 B Gay. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import Vision

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {

    @IBOutlet var sceneView: ARSCNView!
    var request: VNRecognizeTextRequest!
    // Temporal string tracker
    let numberTracker = StringTracker()
    // Vision -> AVF coordinate transform.
    var visionToAVFTransform = CGAffineTransform.identity
    var currentOrientation = UIDeviceOrientation.portrait
    // Region of video data output buffer that recognition should be run on.
    // Gets recalculated once the bounds of the preview layer are known.
    var regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
    // Orientation of text to search for in the region of interest.
    var textOrientation = CGImagePropertyOrientation.up
    // MARK: - Coordinate transforms -
    var bufferAspectRatio: Double!
    // Transform from UI orientation to buffer orientation.
    var uiRotationTransform = CGAffineTransform.identity
    // Transform bottom-left coordinates to top-left.
    var bottomToTopTransform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -1)
    // Transform coordinates in ROI to global coordinates (still normalized).
    var roiToGlobalTransform = CGAffineTransform.identity
    // The pixel buffer being held for analysis; used to serialize Vision requests.
    private var currentBuffer: CVPixelBuffer?
    // Queue for dispatching vision classification requests
    private let visionQueue = DispatchQueue(label: "com.example.apple-samplecode.ARKitVision.serialVisionQueue")
    var shouldFindGiftCardNumber = true
    @IBOutlet weak var labelVisualEffectView: UIVisualEffectView!
    @IBOutlet weak var numberLabel: UILabel!
    @IBOutlet weak var buttonVisualEffectView: UIVisualEffectView!
    @IBOutlet weak var refreshButton: UIButton!
    var backNode: SCNNode?
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set up vision request before letting ViewController set up the camera
        // so that it exists when the first buffer is received.
        request = VNRecognizeTextRequest(completionHandler: recognizeTextHandler)
        
        // Set the view's delegate
        sceneView.delegate = self
        sceneView.session.delegate = self
        
        // Create a new scene
        let scene = SCNScene()
        
        // Set the scene to the view
        sceneView.scene = scene
        
        setupUI()
        calculateRegionOfInterest()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard let referenceImages = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) else {
            fatalError("Missing expected asset catalog resources.")
        }
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        configuration.detectionImages = referenceImages

        // Run the view's session
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        // Only change the current orientation if the new one is landscape or
        // portrait. You can't really do anything about flat or unknown.
        let deviceOrientation = UIDevice.current.orientation
        if deviceOrientation.isPortrait || deviceOrientation.isLandscape {
            currentOrientation = deviceOrientation
        }
        
        // Orientation changed: figure out new region of interest (ROI).
        calculateRegionOfInterest()
    }
    
    // MARK: - Setup -
    
    func setupUI() {
        labelVisualEffectView.effect = nil
        buttonVisualEffectView.effect = nil
        
        labelVisualEffectView.layer.cornerRadius = 12.0
        labelVisualEffectView.layer.masksToBounds = true
        
        buttonVisualEffectView.layer.cornerRadius = 22.0
        buttonVisualEffectView.layer.masksToBounds = true
        
        numberLabel.alpha = 0
        refreshButton.alpha = 0
    }
    
    func calculateRegionOfInterest() {
        
        // ROI changed, update transform.
        setupOrientationAndTransform()
        
        // Update the cutout to match the new ROI.
        DispatchQueue.main.async {
            // Wait for the next run cycle before updating the cutout. This
            // ensures that the preview layer already has its new orientation.
            self.updateCutout()
        }
    }
    
    func updateCutout() {
    }
    
    func setupOrientationAndTransform() {
        // Recalculate the affine transform between Vision coordinates and AVF coordinates.
        
        // Compensate for region of interest.
        let roi = regionOfInterest
        roiToGlobalTransform = CGAffineTransform(translationX: roi.origin.x, y: roi.origin.y).scaledBy(x: roi.width, y: roi.height)
        
        // Compensate for orientation (buffers always come in the same orientation).
        switch currentOrientation {
        case .landscapeLeft:
            textOrientation = CGImagePropertyOrientation.up
            uiRotationTransform = CGAffineTransform.identity
        case .landscapeRight:
            textOrientation = CGImagePropertyOrientation.down
            uiRotationTransform = CGAffineTransform(translationX: 1, y: 1).rotated(by: CGFloat.pi)
        case .portraitUpsideDown:
            textOrientation = CGImagePropertyOrientation.left
            uiRotationTransform = CGAffineTransform(translationX: 1, y: 0).rotated(by: CGFloat.pi / 2)
        default: // We default everything else to .portraitUp
            textOrientation = CGImagePropertyOrientation.right
            uiRotationTransform = CGAffineTransform(translationX: 0, y: 1).rotated(by: -CGFloat.pi / 2)
        }
        
        // Full Vision ROI to AVF transform.
        visionToAVFTransform = roiToGlobalTransform.concatenating(bottomToTopTransform).concatenating(uiRotationTransform)
    }
    
    // MARK: - IBActions -

    @IBAction func refresh(_ sender: UIButton) {
        animateVisualEffectViews(on: false)
        shouldFindGiftCardNumber = true
        let textNode = sceneView.scene.rootNode.childNode(withName: "number", recursively: true)
        textNode?.removeFromParentNode()
    }
    
    // MARK: - Helpers -
    private func animateVisualEffectViews(on: Bool) {
        UIView.animate(withDuration: 0.3) {
            self.labelVisualEffectView.effect = on ? UIBlurEffect(style: UIBlurEffect.Style.systemMaterial) : nil
            self.buttonVisualEffectView.effect = on ? UIBlurEffect(style: UIBlurEffect.Style.systemMaterial) : nil
            self.numberLabel.alpha = on ? 1.0 : 0.0
            self.refreshButton.alpha = on ? 1.0 : 0.0
        }
    }
    
    private func addNumberNode(at point: CGPoint, number: String) {
        guard let hit = sceneView.hitTest(point, options: nil).first else {
            print("NOTHING HIT")
            return
        }
        let node = hit.node
        let coordinates = hit.localCoordinates
        let geo = SCNText(string: number, extrusionDepth: 0.005)
        geo.font = UIFont.systemFont(ofSize: 12.0)
        geo.firstMaterial?.diffuse.contents = UIColor.black
        let childNode = SCNNode()
        childNode.name = "number"
        childNode.position = coordinates
        childNode.geometry = geo
        node.addChildNode(childNode)
    }
    
    // MARK: - ARSCNViewDelegate -

    // Override to create and configure nodes for anchors added to the view's session.
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let imageAnchor = anchor as? ARImageAnchor, imageAnchor.name == "back" else {
            return nil
        }
        let node = SCNNode()
        let childNode = SCNNode()
        let plane = SCNPlane(width: imageAnchor.referenceImage.physicalSize.width, height: imageAnchor.referenceImage.physicalSize.height)
        childNode.geometry = plane
        childNode.geometry?.firstMaterial?.transparency = 1.0
        childNode.eulerAngles.x = -Float.pi * 0.5
        node.addChildNode(childNode)
        backNode = node
        return node
    }

    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        
    }
    
    // MARK: - ARSessionDelegate -
    
    // Pass camera frames received from ARKit to Vision (when not already processing one)
    /// - Tag: ConsumeARFrames
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Do not enqueue other buffers for processing while another Vision task is still running.
        // The camera stream has only a finite amount of buffers available; holding too many buffers for analysis would starve the camera.
        guard currentBuffer == nil, shouldFindGiftCardNumber, case .normal = frame.camera.trackingState else {
            return
        }
        
        // Retain the image buffer for Vision processing.
        self.currentBuffer = frame.capturedImage
        
        classifyCurrentImage()
    }
    
    // Run the Vision+ML classifier on the current image buffer.
    /// - Tag: ClassifyCurrentImage
    private func classifyCurrentImage() {
        // Configure for running in real-time.
        request.recognitionLevel = .fast
        request.usesCPUOnly = true
        // Language correction won't help recognizing gift card numbers. It also
        // makes recognition slower.
        request.usesLanguageCorrection = false
        // Only run on the region of interest for maximum speed.
        request.regionOfInterest = regionOfInterest
        
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: currentBuffer!, orientation: textOrientation)
        visionQueue.async {
            do {
                // Release the pixel buffer when done, allowing the next buffer to be processed.
                defer { self.currentBuffer = nil }
                try requestHandler.perform([self.request])
            } catch {
                print("Error: Vision request failed with error \"\(error)\"")
            }
        }
    }
    
    // MARK: - Text recognition -
    
    // Vision recognition handler.
    func recognizeTextHandler(request: VNRequest, error: Error?) {
        var numbers = [String]()
        var redBoxes = [CGRect]() // Shows all recognized text lines
        var greenBoxes = [CGRect]() // Shows words that might be serials
        
        guard let results = request.results as? [VNRecognizedTextObservation] else {
            return
        }
        
        let maximumCandidates = 1
        
        for visionResult in results {
            guard let candidate = visionResult.topCandidates(maximumCandidates).first else { continue }
            
            // Draw red boxes around any detected text, and green boxes around
            // any detected phone numbers. The phone number may be a substring
            // of the visionResult. If a substring, draw a green box around the
            // number and a red box around the full string. If the number covers
            // the full result only draw the green box.
            var numberIsSubstring = true
            
            if let result = candidate.string.extractGiftCard() {
                let (range, number) = result
                // Number may not cover full visionResult. Extract bounding box
                // of substring.
                if let box = try? candidate.boundingBox(for: range)?.boundingBox {
                    numbers.append(number)
                    greenBoxes.append(box)
                    numberIsSubstring = !(range.lowerBound == candidate.string.startIndex && range.upperBound == candidate.string.endIndex)
                }
            }
            if numberIsSubstring {
                redBoxes.append(visionResult.boundingBox)
            }
        }
        
        // Log any found numbers.
        numberTracker.logFrame(strings: numbers)
        show(boxGroups: [(color: UIColor.red.cgColor, boxes: redBoxes), (color: UIColor.green.cgColor, boxes: greenBoxes)])
        
        // Check if we have any temporally stable numbers.
        if let sureNumber = numberTracker.getStableString() {
//            showString(string: sureNumber)
            if backNode != nil {
                DispatchQueue.main.async {
                    self.numberLabel.text = sureNumber
                    self.animateVisualEffectViews(on: true)
                    if let box = greenBoxes.first {
                        let point = self.convertFromCamera(CGPoint(x: box.midX, y: box.midY), view: self.sceneView)
                        self.addNumberNode(at: point, number: sureNumber)
                    } else {
                        print("NO GREEN BOX")
                    }
                }
                
                numberTracker.reset(string: sureNumber)
                shouldFindGiftCardNumber = false
            } else {
                numberTracker.reset(string: sureNumber)
            }
        }
    }
    
    // MARK: - Bounding box drawing -
    
    // Draw a box on screen. Must be called from main queue.
    var boxLayer = [CAShapeLayer]()
    func draw(rect: CGRect, color: CGColor) {
        let layer = CAShapeLayer()
        layer.opacity = 0.5
        layer.borderColor = color
        layer.borderWidth = 1
        layer.frame = rect
        boxLayer.append(layer)
        sceneView.layer.insertSublayer(layer, at: 1)
    }
    
    // Remove all drawn boxes. Must be called on main queue.
    func removeBoxes() {
        for layer in boxLayer {
            layer.removeFromSuperlayer()
        }
        boxLayer.removeAll()
    }
    
    typealias ColoredBoxGroup = (color: CGColor, boxes: [CGRect])
    
    // Draws groups of colored boxes.
    func show(boxGroups: [ColoredBoxGroup]) {
        DispatchQueue.main.async {
            let layer = self.sceneView.layer
            self.removeBoxes()
            for boxGroup in boxGroups {
                let color = boxGroup.color
                for box in boxGroup.boxes {
//                    let rect = layer.layerRectConverted(fromMetadataOutputRect: box.applying(self.visionToAVFTransform))
//                    self.draw(rect: rect, color: color)
                }
            }
        }
    }
    
    func convertFromCamera(_ point: CGPoint, view sceneView: ARSCNView) -> CGPoint {
        switch currentOrientation {
        case .portrait, .unknown:
            return CGPoint(x: point.y * sceneView.frame.width, y: point.x * sceneView.frame.height)
        case .landscapeLeft:
            return CGPoint(x: (1 - point.x) * sceneView.frame.width, y: point.y * sceneView.frame.height)
        case .landscapeRight:
            return CGPoint(x: point.x * sceneView.frame.width, y: (1 - point.y) * sceneView.frame.height)
        case .portraitUpsideDown:
            return CGPoint(x: (1 - point.y) * sceneView.frame.width, y: (1 - point.x) * sceneView.frame.height)
        @unknown default:
            return .zero
        }
    }
}
