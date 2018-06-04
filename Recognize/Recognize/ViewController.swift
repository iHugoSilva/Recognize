//
//  ViewController.swift
//  Recognize
//
//  Created by Hugo Silva on 30/05/2018.
//  Copyright © 2018 Hugo Silva. All rights reserved.
//

import UIKit
import CoreML
import Vision 
class ViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    @IBOutlet weak var imageView: UIImageView!
    
    let imagePicker = UIImagePickerController()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        imagePicker.delegate = self
        imagePicker.sourceType = .camera
        imagePicker.allowsEditing = false
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        
        //If the data can be downcast into an UIImage datatype than
       if let userPickedImage = info[UIImagePickerControllerOriginalImage] as? UIImage{
            imageView.image = userPickedImage
        
        guard let ciimage = CIImage(image: userPickedImage) else{
            fatalError("Could not convert UIImage to CIImage")
        }
        
        detect(image: ciimage)
    }
        
        imagePicker.dismiss(animated: true, completion: nil)
    }
    
    func detect(image: CIImage){
        guard let model = try? VNCoreMLModel(for: Inceptionv3().model) else{
            fatalError("Loading CoreML Model Failed")
        }
        
        let request = VNCoreMLRequest(model: model) { (request, error) in
            guard let results = request.results as? [VNClassificationObservation] else{
                fatalError("Model Failed to process image")
                }
                    print(results)
            
            }
        
            let handler = VNImageRequestHandler(ciImage: image)
        
            do {
                try handler.perform([request])
        }
            catch{
                print(error)
        }
    }

    
    
    
    @IBAction func cameraTouched(_ sender: UIBarButtonItem) {
        
        present(imagePicker, animated: true, completion: nil)
    }
    
    

}

