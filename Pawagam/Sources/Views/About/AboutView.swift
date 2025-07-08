//
//  AboutView.swift
//  Pawagam
//
//  Created by Khai Yuan Yap on 19/06/2025.
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {
                    // App Header
                    appHeaderSection
                    
                    // Important Warning Section
                    warningSection
                    
                    // Tips Section
                    tipsSection
                    
                    // Technical Specs
                    technicalSection
                    
                    // Credits Section
                    creditsSection
                    
                    // Additional space at bottom
                    Spacer(minLength: 60)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .background(.thinMaterial, ignoresSafeAreaEdges: .all)
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private var appHeaderSection: some View {
        VStack(spacing: 20) {
                       
    VStack(spacing: 8) {
        HStack(spacing: 11) {
                        Text("Pawagam")
                    }
                    .font(.system(size: 35, design: .monospaced))
                    .foregroundStyle(.white)
                
                Text("Raw Video Recording")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                
                // Version
                Text("Version 1.0.0")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 4)
            }
        }
    }

    private var warningSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "exclamationmark.triangle.fill", title: "Important Warnings")
            
            VStack(spacing: 12) {
                warningCard(
                    icon: "xmark.circle.fill",
                    title: "Frame Drops",
                    warning: "Extended recording and high frame rates may result in dropped frames due to intensive processing requirements."
                )
                
                warningCard(
                    icon: "exclamationmark.octagon.fill",
                    title: "App Stability",
                    warning: "The app may become unstable after continuous recording sessions. Regular breaks are recommended."
                )
                
                warningCard(
                    icon: "hand.raised.fill",
                    title: "Critical Use Warnings",
                    warning: "Do not use for mission-critical projects, important events, or high-stakes productions without thorough testing."
                )
            }
        }
    }
    
    private func warningCard(icon: String, title: String, warning: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.red)
                .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                
                Text(warning)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.red.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "lightbulb.fill", title: "Pro Tips")
            
            VStack(spacing: 12) {
                tipCard(
                    icon: "battery.100",
                    title: "Battery Life",
                    tip: "CinemaDNG recording is intensive. Use external power for extended shoots."
                )
                
                tipCard(
                    icon: "externaldrive.fill",
                    title: "Storage",
                    tip: "Use fast external storage for best performance. USB-C SSD drives work great."
                )
                
                tipCard(
                    icon: "thermometer.sun.fill",
                    title: "Heat Management",
                    tip: "Allow cooling breaks during long recordings to prevent thermal throttling."
                )
                
                tipCard(
                    icon: "chart.bar.fill",
                    title: "Exposure",
                    tip: "Use the histogram to ensure proper exposure. Avoid clipping highlights."
                )
            }
        }
    }
    
    private func tipCard(icon: String, title: String, tip: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.orange)
                .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                
                Text(tip)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private var technicalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "gear", title: "Technical Specifications")
            
            VStack(spacing: 12) {
                specRow(label: "Format", value: "CinemaDNG")
                specRow(label: "Color Depth", value: "14-bit RAW")
                specRow(label: "Frame Rates", value: "20, 24, 30, 60, 120 fps")
                specRow(label: "Resolution", value: "Device dependent")
                specRow(label: "Metadata", value: "Embedded")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
    
    private func specRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
    
    private var creditsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(icon: "person.fill", title: "Credits")
            
            VStack(spacing: 16) {
                creditCard(
                    title: "Developer",
                    subtitle: "Khai Yuan Yap",
                    description: "Malaysian indie developer"
                )
            }
        }
    }
    
    private func creditCard(title: String, subtitle: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)
                .tracking(0.5)
            
            Text(subtitle)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            
            Text(description)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
            
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}
