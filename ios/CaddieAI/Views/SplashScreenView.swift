//
//  SplashScreenView.swift
//  CaddieAI
//
//  Branded launch splash screen.
//

import SwiftUI
import UIKit

struct SplashScreenView: View {
    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var brandOpacity: Double = 0

    /// Orbitron ExtraBold (weight 800) for the CaddieAI wordmark.
    private static let orbitronFont: Font = {
        let size: CGFloat = 38
        if let uiFont = UIFont(name: "Orbitron-ExtraBold", size: size) {
            return Font(uiFont)
        }
        return .system(size: size, weight: .heavy, design: .rounded)
    }()

    private static let caddieColor = Color(red: 0x23/255, green: 0x36/255, blue: 0x7D/255) // #23367D
    private static let aiColor = Color(red: 0xC5/255, green: 0x03/255, blue: 0x1A/255)     // #C5031A

    var body: some View {
        ZStack {
            Color(red: 232/255, green: 233/255, blue: 235/255) // #E8E9EB
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

                // App name — Orbitron ExtraBold wordmark
                (Text("Caddie").foregroundStyle(Self.caddieColor)
                 + Text("AI").foregroundStyle(Self.aiColor))
                    .font(Self.orbitronFont)
                    .tracking(0.5)
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
