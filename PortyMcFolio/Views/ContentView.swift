import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    @State private var isShowingSearch = false

    var body: some View {
        ZStack {
            Group {
                if appState.portfolioRootURL == nil {
                    FolderPickerView()
                } else if appState.isShowingSettings {
                    AppSettingsView()
                } else if let project = appState.selectedProject {
                    ProjectDetailView(project: project)
                        .id(project.uid)
                } else {
                    ProjectListView()
                }
            }

            // Search palette overlay
            if isShowingSearch {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .onTapGesture { isShowingSearch = false }
                    .transition(.opacity)

                VStack {
                    SearchPalette(isPresented: $isShowingSearch)
                        .padding(.top, 60)
                    Spacer()
                }
                .transition(.opacity)
            }

        }
        .overlay {
            if !appState.isReady {
                SplashView()
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if let message = appState.toastMessage {
                ToastView(message: message)
                    .padding(.bottom, DT.Spacing.xl)
                    .transition(.opacity.combined(with: .offset(y: 8)))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.toastMessage)
        .background(theme.colors.background.ignoresSafeArea())
        .toolbarBackground(theme.colors.background, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .animation(.easeOut(duration: 0.15), value: isShowingSearch)
        .animation(.easeOut(duration: 0.3), value: appState.isReady)
        .onAppear {
            appState.loadSavedRoot()
            appState.loadLayoutPreferences()
        }
        .background {
            // Cmd+K to toggle search — hidden button ensures it works globally
            Button("") {
                isShowingSearch.toggle()
            }
            .keyboardShortcut("k", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        }
    }
}
