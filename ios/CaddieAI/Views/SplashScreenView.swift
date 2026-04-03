//
//  SplashScreenView.swift
//  CaddieAI
//
//  Branded launch splash screen.
//

import SwiftUI

struct SplashScreenView: View {
    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var brandOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo (large)
                Image("SubcultureLogo")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 260, height: 260)
                    .clipShape(Circle())
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)

                Spacer().frame(height: 32)

                // App name
                Text("CaddieAI")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .opacity(textOpacity)

                Spacer()

                // "Brought to you by" + wordmark
                VStack(spacing: 12) {
                    Text("Brought to you by")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.black.opacity(0.45))

                    Image("SubcultureWordmark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200)
                }
                .opacity(brandOpacity)
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                textOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.5)) {
                brandOpacity = 1.0
            }
        }
    }
}

#Preview {
    SplashScreenView()
}
