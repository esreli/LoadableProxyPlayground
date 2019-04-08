// Copyright 2018 Esri.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import UIKit
import PlaygroundSupport

// Import the ArcGIS framework
// Note: Make sure you open the Playground workspace (*.xcworkspace file) and build the project in order to make the ArcGIS framework available to this playground
import ArcGIS

protocol LoadableSurrogateProxy: AGSLoadable where Self: NSObject {
    
    // MARK: AGSLoadableBase
    
    func doStartLoading(_ retrying: Bool, completion: @escaping (Error?) -> Void)
    func doCancelLoading() -> Bool
    
    // MARK: LoadableSurrogateProxy
    
    func loadStatusDidChange(_ status: AGSLoadStatus)
    func loadErrorDidChange(_ error: Error?)
}

/// Allows an object to adhere to `AGSLoadable` via `AGSLoadableBase` in the situation where it cannot subclass `AGSLoadableBase` directly.
///
/// This allows a class to offload async loading and load state to the ArcGIS SDK, keeping in mind thread safety.
///

class LoadableSurrogate: AGSLoadableBase {
    
    weak var proxy: LoadableSurrogateProxy? {
        didSet {
            proxy?.loadStatusDidChange(loadStatus)
            proxy?.loadErrorDidChange(loadError)
        }
    }
    
    private var kvo: Set<NSKeyValueObservation> = []
    
    override init() {
        
        super.init()
        
        let loadStatusObservation = self.observe(\.loadStatus) { [weak self] (_, _) in
            
            guard let self = self else { return }
            
            self.proxy?.loadStatusDidChange(self.loadStatus)
        }
        
        kvo.insert(loadStatusObservation)
        
        let loadErrorObservation = self.observe(\.loadError) { [weak self] (_, _) in
            
            guard let self = self else { return }
            
            self.proxy?.loadErrorDidChange(self.loadError)
        }
        
        kvo.insert(loadErrorObservation)
    }
    
    private let UnknownError = NSError(domain: "LoadableSurrogate.UnknownError", code: 1, userInfo: [NSLocalizedDescriptionKey: "An unknown error occurred."])
    
    override func doStartLoading(_ retrying: Bool) {
        
        // We want to unwrap the delegate, if we have one.
        if let proxy = proxy {
            
            // Call start loading on the delegate
            proxy.doStartLoading(retrying) { [weak self] (error) in
                
                guard let self = self else { return }
                
                // Finish loading with the reponse from the delegate.
                self.loadDidFinishWithError(error)
            }
        }
        else {
            // No delegate, finish loading.
            loadDidFinishWithError(UnknownError)
        }
    }
    
    private let CancelledError = NSError(domain: "LoadableSurrogate.CancelledError", code: NSUserCancelledError, userInfo: [NSLocalizedDescriptionKey: "User did cancel."])

    override func doCancelLoading() {
        
        // Call cancel delegate method.
        if proxy?.doCancelLoading() == true {
            
            self.loadDidFinishWithError(CancelledError)
        }
    }
}

class KermitLoader: NSObject, LoadableSurrogateProxy {
    
    // MARK: Loadable Surrogate
    
    private let surrogate = LoadableSurrogate()
    
    override init() {
        super.init()
        surrogate.proxy = self
    }
    
    // MARK: AGSLoadable
    
    //
    // Instead of writing a custom async implementation,
    // put the surrogate to work for you.
    //
    // The following 3 methods can be copied and pasted directly.
    //
    
    func load(completion: ((Error?) -> Void)? = nil) {
        surrogate.load(completion: completion)
    }
    
    func retryLoad(completion: ((Error?) -> Void)? = nil) {
        surrogate.retryLoad(completion: completion)
    }
    
    func cancelLoad() {
        surrogate.cancelLoad()
    }
    
    //
    // KVO-compliant `AGSLoadable` properties.
    //
    
    @objc var loadStatus: AGSLoadStatus = .unknown
    
    @objc var loadError: Error? = nil
    
    // MARK: LoadableSurrogateProxy
    
    //
    // Proxy informs of changes to `loadStatus` and `loadError`.
    //
    
    func loadStatusDidChange(_ status: AGSLoadStatus) {
        self.loadStatus = status
    }
    
    func loadErrorDidChange(_ error: Error?) {
        self.loadError = error
    }
    
    //
    // Follows the pattern found in `AGSLoadableBase`.
    //
    
    private let kermitURL = URL(string: "https://c1.staticflickr.com/2/1033/1024297684_582bc1c05a_b.jpg")!
    
    private var kermitSessionDataTask: URLSessionDataTask?
    
    var kermitImage: UIImage? = nil
    
    //
    // Call the completion callback without an error if the load was successful.
    //
    
    func doStartLoading(_ retrying: Bool, completion: @escaping (Error?) -> Void) {
        
        if retrying {
            
            let previousDataTask = kermitSessionDataTask
            kermitSessionDataTask = nil
            previousDataTask?.cancel()
            kermitImage = nil
        }
        
        kermitSessionDataTask = URLSession.shared.dataTask(with: kermitURL) { [weak self] data, response, error in
            
            guard let self = self else { return }
            
            if let data = data, let image = UIImage(data: data) {
                self.kermitImage = image
            }
            
            if response == self.kermitSessionDataTask?.response {
                completion(error)
            }
        }
        
        kermitSessionDataTask!.resume()
    }
    
    func doCancelLoading() -> Bool {
        
        kermitSessionDataTask?.cancel()
        kermitSessionDataTask = nil
        kermitImage = nil
        
        // Return `true` if you want the surrogate to supply a generic cancel error.
        return false
    }
}


let imageView = UIImageView(frame: CGRect(origin: .zero, size: CGSize(width: 500, height: 500)))
imageView.contentMode = .scaleAspectFill

PlaygroundPage.current.liveView = imageView

let kermitLoader = KermitLoader()

kermitLoader.load { (error) in

    if let error = error {
        print("Error: \(error.localizedDescription)")
    }

    imageView.image = kermitLoader.kermitImage
}

//kermitLoader.cancelLoad()
//
//DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
//
//    kermitLoader.retryLoad { (error) in
//
//        if let error = error {
//            print("Error: \(error.localizedDescription)")
//        }
//
//        imageView.image = kermitLoader.kermitImage
//    }
//}

