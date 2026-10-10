import SwiftUI

struct IChartLegalLinksView: View {
    var body: some View {
        HStack(spacing: 20) {
            Link("Terms of Use", destination: IChartLegalLinks.termsURL)
                .frame(minHeight: 44)
            Link("Privacy Policy", destination: IChartLegalLinks.privacyURL)
                .frame(minHeight: 44)
        }
        .font(.footnote)
        .accessibilityElement(children: .contain)
    }
}
