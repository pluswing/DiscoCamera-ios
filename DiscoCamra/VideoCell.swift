//
//  VideoCell.swift
//  DiscoCamera
//
//  Created by pluswing on 2018/10/17.
//  Copyright © 2018 pluswing. All rights reserved.
//

import UIKit

class VideoCell : UICollectionViewCell {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.xibViewSet()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
        self.xibViewSet()
    }
    
    internal func xibViewSet() {
        if let view = Bundle.main.loadNibNamed("VideoCell", owner: self, options: nil)?.first as? UIView {
            view.frame = self.bounds
            self.addSubview(view)
        }
    }
}
