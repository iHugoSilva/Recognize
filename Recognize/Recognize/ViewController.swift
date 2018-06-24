//
//  ViewController.swift
//  iRecognize
//
//  Created by Hugo Silva on 30/05/2018.
//  Copyright © 2018 Hugo Silva. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import Vision
import CoreML

class ViewController: UIViewController, ARSCNViewDelegate {
    
    // SCENE
    @IBOutlet var sceneView: ARSCNView!
    let textDepth : Float = 0.01 // the 'depth' of 3D text
    var latestPrediction : String = "…" // a variable containing the latest CoreML prediction
    
    // COREML
    var visionRequests = [VNRequest]()
    let dispatchQueueML = DispatchQueue(label: "dispatchQueueML") // A Serial Queue
    //Serial queues (also known as private dispatch queues) execute one task at a time in the order in which they are added to the queue.
    @IBOutlet weak var debugArea: UITextView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        sceneView.delegate = self
        
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = false
        
        // Create a new scene
        let scene = SCNScene()
        
        // Set the scene to the view
        sceneView.scene = scene
        
        // Enable Default Lighting - makes the 3D text to stand out a bit better.
        sceneView.autoenablesDefaultLighting = true
        
        // Tap Gesture Recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.handleTap(gestureRecognize:)))
        view.addGestureRecognizer(tapGesture)
        
        // Set up Vision Model
        guard let selectedModel = try? VNCoreMLModel(for: Inceptionv3().model) //This 'Inceptionv3' model can be replaced with other models
        else
        {
            fatalError("Failure loading the model")
        }
        
        // Set up Vision-CoreML Request
        let classificationRequest = VNCoreMLRequest(model: selectedModel, completionHandler: classificationCompleteHandler)
        classificationRequest.imageCropAndScaleOption = VNImageCropAndScaleOption.centerCrop // Crop from centre of images and scale it to appropriate size.
        visionRequests = [classificationRequest]
        
        // Begin Loop to Update CoreML
        loopCoreMLUpdate()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        // Enable plane detection
        configuration.planeDetection = .horizontal
        
        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
//    // ARSCNViewDelegate
//
//    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
//        DispatchQueue.main.async {
//            // Do any desired updates to SceneKit here.
//        }
//    }
    
    // Status Bar: Hide
    override var prefersStatusBarHidden : Bool {
        return true
    }
    
    // Interaction
    
    @objc func handleTap(gestureRecognize: UITapGestureRecognizer)
    {
        // HIT TEST : REAL WORLD
        // Get Screen Centre
        let screenCentre : CGPoint = CGPoint(x: self.sceneView.bounds.midX, y: self.sceneView.bounds.midY)
        
        let arHitTestResults : [ARHitTestResult] = sceneView.hitTest(screenCentre, types: [.featurePoint])
        
        if let closestResult = arHitTestResults.first
        {
            // Get Coordinates of HitTest
            let transform : matrix_float4x4 = closestResult.worldTransform
            let worldCoord : SCNVector3 = SCNVector3Make(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            
            // Create 3D Text
            let node : SCNNode = createNewRealWorldTextParentNode(latestPrediction)
            sceneView.scene.rootNode.addChildNode(node)
            node.position = worldCoord
        }
    }
    
    func createNewRealWorldTextParentNode(_ text : String) -> SCNNode
    {
        // Reducing size of letters, smoothness, etc.
        // Using 3D objects can overload the device and therefore make the app crash, so watch out for the size and thinkness of letters/objects.
        
        // TEXT CONSTRAINT
        let billboardConstraint = SCNBillboardConstraint() // A constraint that orients a node to always point toward the current camera.
        billboardConstraint.freeAxes = SCNBillboardAxis.Y //Parallel to the screen
        
        // TEXT
        let realWorldLabel = SCNText(string: text, extrusionDepth: CGFloat(textDepth))
        realWorldLabel.alignmentMode = kCAAlignmentCenter  //Text is visually center aligned.
        //Diffuse:
        //describes the amount and color of light reflected equally in all directions from each point on the material’s surface.
        //Specular:
        //describes the amount and color of light reflected by the material directly toward the viewer, forming a bright highlight on the surface and simulating a glossy or shiny appearance.
        realWorldLabel.firstMaterial?.diffuse.contents = UIColor.blue
        realWorldLabel.firstMaterial?.specular.contents = UIColor.black
        realWorldLabel.firstMaterial?.isDoubleSided = true
        // bubble.flatness // setting this too low can cause crashes.
        realWorldLabel.chamferRadius = CGFloat(textDepth)
        // Text Size -> Adding the extension at line '255' solved the big text problem
        var font = UIFont(name: "Futura", size: 0.20)
        font = font?.withTraits(traits: .traitBold)
        realWorldLabel.font = font
        
        // TEXT NODE
        let (minBound, maxBound) = realWorldLabel.boundingBox
        let realWorldLabelNode = SCNNode(geometry: realWorldLabel)
        // Centre Node - to Centre-Bottom point
        realWorldLabelNode.pivot = SCNMatrix4MakeTranslation( (maxBound.x - minBound.x)/2, minBound.y, textDepth/2)
        // Reduce default text size
        realWorldLabelNode.scale = SCNVector3Make(0.1, 0.1, 0.1)
        
        // CENTRE POINT NODE
        let sphere = SCNSphere(radius: 0.005)
        sphere.firstMaterial?.diffuse.contents = UIColor.cyan
        let sphereNode = SCNNode(geometry: sphere)
        
        // TEXT PARENT NODE
        let realWorldLabelNodeParent = SCNNode()
        realWorldLabelNodeParent.addChildNode(realWorldLabelNode)
        realWorldLabelNodeParent.addChildNode(sphereNode)
        realWorldLabelNodeParent.constraints = [billboardConstraint]
        
        return realWorldLabelNodeParent
    }
    
    // MARK: - CoreML Vision Handling
    
    func loopCoreMLUpdate() {
        // Continuously run CoreML whenever it's ready.
        
        dispatchQueueML.async {
            // 1. Run Update.
            self.updateCoreML()
            
            // 2. Loop this function.
            self.loopCoreMLUpdate()
        }
        
    }
    
    func classificationCompleteHandler(request: VNRequest, error: Error?) {
        // Catch Errors
        if error != nil
        {
            print("Error: " + (error?.localizedDescription)!)
            return
        }
        guard let observations = request.results
        else
        {
            print("No results")
            return
        }
        
        // Get Classifications
        let classifications = observations[0...1] // top 2 results
            .compactMap({ $0 as? VNClassificationObservation })
            .map({ "\($0.identifier) \(String(format:"- %.2f", $0.confidence))" })
            .joined(separator: "\n")
        
        // DispatchQueue manages the execution of work items.
        DispatchQueue.main.async
        {
            // Print Classifications
            print(classifications)
            print("--")
          
            // Display Debug Text on the Debug Area UITextView instead of the log
            var debugText:String = ""
            debugText += classifications
            self.debugArea.text = debugText
            // Store the latest prediction
            var objectName:String = "…"
            objectName = classifications.components(separatedBy: "-")[0]
            //The [0] denotes which string we want to return from the array by it's index
            objectName = objectName.components(separatedBy: ",")[0]
            self.latestPrediction = objectName
            
        }
    }
    
    func updateCoreML()
    {
        
        // The pixel buffer stores an image in main memory, so we are going to use it to keep it showing on the screen.
        let pixbuff : CVPixelBuffer? = (sceneView.session.currentFrame?.capturedImage)
        if pixbuff == nil { return }
        let ciImage = CIImage(cvPixelBuffer: pixbuff!) //We use the Core Image Image (CIImage) to take advantage of the built-in Core Image filters when processing images.
        
        // Prepare CoreML/Vision Request
        let imageRequestHandler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        
        // Run Image Request
        do
        {
            //Scheduling Vision requests to be performed.
            try imageRequestHandler.perform(self.visionRequests)
        }
        catch 
        {
            print(error)
        }
        
    }
    
}
extension UIFont
{
    // Base on a suggestion from Stackoverflow: https://stackoverflow.com/questions/4713236/how-do-i-set-bold-and-italic-on-uilabel-of-iphone-ipad
    func withTraits(traits:UIFontDescriptorSymbolicTraits...) -> UIFont
    {
        let descriptor = self.fontDescriptor.withSymbolicTraits(UIFontDescriptorSymbolicTraits(traits))
        return UIFont(descriptor: descriptor!, size: 0)
    }
}

