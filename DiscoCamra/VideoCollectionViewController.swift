//
//  VideoCollectionView.swift
//  DiscoCamera
//
//  Created by pluswing on 2018/10/17.
//  Copyright © 2018 pluswing. All rights reserved.
//

import UIKit
import Photos

class VideoCollectionViewController : UIViewController {

    @IBOutlet weak var collectionView: UICollectionView!
    
    var videos = Array<AVPlayerItem>()
    let phmov = PHImageManager()
    let margin: CGFloat = 10.0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(UINib(nibName: "VideoCellView", bundle: nil), forCellWithReuseIdentifier: "VideoCellView")
        
        loadVideos()
    }
    
    func loadVideos() {
        //ロード中がわかるようにインジケータを表示
        let ai = UIActivityIndicatorView.init(style: UIActivityIndicatorView.Style.whiteLarge)
        ai.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        ai.center = self.view.center
        ai.hidesWhenStopped = true
        self.view.addSubview(ai)
        ai.startAnimating()
        
        let assets:PHFetchResult = PHAsset.fetchAssets(with: PHAssetMediaType.video, options: nil)

        var responseCount = 0
        let lockObj = NSObject()
        assets.enumerateObjects({(obj, index, stop) -> Void in
            self.phmov.requestPlayerItem(forVideo: assets[index], options: nil, resultHandler: {(playerItem, info) -> Void in

                objc_sync_enter(lockObj)
                responseCount += 1
                if let i = playerItem {
                    self.videos.append(i)
                }
                objc_sync_exit(lockObj)

                if responseCount == assets.count {
                    DispatchQueue.main.async {
                        self.collectionView.reloadData()
                        ai.stopAnimating()
                        ai.removeFromSuperview()
                    }
                }
            })
        })
    }
    
    @IBAction func close(_ sender: Any) {
        self.dismiss(animated: true, completion: nil)
    }
}

extension VideoCollectionViewController : UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        let item = self.videos[indexPath.row]
        let next = storyboard!.instantiateViewController(withIdentifier: "videoPlayerViewController") as! VideoPlayerViewController
        next.item = item
        self.present(next, animated: true, completion: nil)
        
    }
}

extension VideoCollectionViewController : UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.videos.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell:VideoCellView = collectionView.dequeueReusableCell(withReuseIdentifier: "VideoCellView", for: indexPath) as! VideoCellView
        let item = self.videos[indexPath.row]

        let asset1:AVAsset = item.asset
        let gene = AVAssetImageGenerator(asset:asset1)
        gene.maximumSize = CGSize(width:self.view.frame.size.width/4, height:self.view.frame.size.width/4)
        let capImg = try! gene.copyCGImage(at: asset1.duration, actualTime: nil)
        
        //切り出した画像をイメージビューで表示
        cell.imageView.image = UIImage.init(cgImage: capImg)
        
        //動画の尺をラベルに表示
        let sec:Float64 = asset1.duration.seconds
        let sec2:Int = Int(sec)
        cell.durationLabel.text = String(format:"%02d:%02d",sec2/60,sec2%60)
        
        return cell
    }
}

extension VideoCollectionViewController: UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        // 例えば端末サイズを 3 列にする場合
        let width: CGFloat = UIScreen.main.bounds.width / 3 - margin*2
        let height = width
        return CGSize(width: width, height: height)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: margin, left: margin, bottom: margin, right: margin)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return margin
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return margin
    }
}
