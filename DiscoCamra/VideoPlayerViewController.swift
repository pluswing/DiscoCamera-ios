//
//  VideoPlayerViewController.swift
//  DiscoCamera
//
//  Created by pluswing on 2018/10/18.
//  Copyright © 2018 pluswing. All rights reserved.
//

import UIKit
import AVFoundation

class VideoPlayerViewController : UIViewController {
    
    @IBOutlet weak var videoContainer : UIView!
    
    public var item: AVPlayerItem?
    var player: AVPlayer?
    
    override func viewDidAppear(_ animated: Bool) {
        
        if let i = item {
            let pa = AVPlayerItem.init(asset: i.asset)
            player = AVPlayer.init(playerItem: pa)
        }

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = videoContainer.bounds
        videoContainer.layer.addSublayer(playerLayer)
        
        player?.play()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        player?.pause()
        player = nil
    }

    @IBAction func close(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
    }

    @IBAction func share(_ sender: Any) {
        guard let i = item else { return }
        let asset = i.asset as! AVURLAsset
        let activityVc = UIActivityViewController(activityItems: [asset.url], applicationActivities: nil)
        self.present(activityVc, animated: true, completion: nil)
    }
}
