//
//  ContentView.swift
//  ZoomWithSwiftUI
//
//  Created by Pawan Sharma on 29/05/21.
//

import SwiftUI

struct ContentView: View {
  var body: some View {
      VStack {
        ZoomableScrollView {
          Image("Xcode Black")
            .background(Color.red)
        }
        Spacer()
      }
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}
