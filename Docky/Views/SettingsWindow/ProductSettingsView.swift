//
//  ProductSettingsView.swift
//  Docky
//

import SwiftUI

struct ProductSettingsView: View {
    @ObservedObject private var product = ProductService.shared
    @State private var licenseKey: String = ""

    var body: some View {
        Form {
            Section("Current Plan") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Tier")
                            .font(.headline)

                        Spacer()

                        Text(product.currentTier.title)
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .top) {
                        Text(product.registrationStatus.title)
                            .font(.headline)

                        Spacer()

                        if product.currentTier == .pro {
                            ProBadge()
                        }
                    }

                    Text(product.registrationStatus.message)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Register Product") {
                VStack(alignment: .leading, spacing: 12) {
                    SecureField(product.hasStoredLicenseKey ? "Replace License Key" : "License Key", text: $licenseKey)
                        .textFieldStyle(.roundedBorder)
                        .disabled(product.isVerifyingRegistration)

                    Text("License keys are verified with Gumroad and then stored locally on this Mac. Each license can be activated on up to \(ProductService.maximumActivationCount) Macs.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if product.isVerifyingRegistration {
                        ProgressView("Verifying License...")
                    }

                    HStack(spacing: 10) {
                        Button("Verify License") {
                            product.registerProduct(licenseKey: licenseKey)
                            licenseKey = ""
                        }
                        .disabled(licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || product.isVerifyingRegistration)

                        Button("Clear Registration") {
                            product.clearRegistration()
                            syncFieldsFromService()
                        }
                        .disabled((!product.hasStoredLicenseKey && product.currentTier == .free) || product.isVerifyingRegistration)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Docky Pro Features") {
                ForEach(ProductFeature.productSettingsFeatures) { feature in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(feature.title)
                                .font(.headline)
                            Spacer()
                            ProBadge()
                        }

                        Text(feature.summary)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .onAppear(perform: syncFieldsFromService)
    }

    private func syncFieldsFromService() {
        licenseKey = ""
    }
}
