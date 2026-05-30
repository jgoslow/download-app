//
//  BasnWidgetBundle.swift
//  BasnWidget
//
//  Created by Jonas Goslow on 5/30/26.
//

import WidgetKit
import SwiftUI

@main
struct BasnWidgetBundle: WidgetBundle {
    var body: some Widget {
        BasnWidget()
        BasnWidgetControl()
        BasnWidgetLiveActivity()
    }
}
