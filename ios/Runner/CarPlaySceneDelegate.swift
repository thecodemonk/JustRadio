import CarPlay
import Foundation
import UIKit

/// CarPlay scene delegate for JustRadio. Scaffolding only — the templates
/// and hookups are complete, but the scene will not actually connect at
/// runtime until the app is granted the `com.apple.developer.carplay-audio`
/// entitlement by Apple (weeks-long request). Until then, this file
/// compiles and ships dormant; phone playback is unaffected.
///
/// The scene runs in a separate UIScene from Flutter's window scene, so it
/// reads browse-tree data (favorites / recent / genres) from UserDefaults
/// rather than talking to Dart. `AudioPlayerPlugin` mirrors those lists on
/// every change via the `sync*` method channel entry points — same
/// mechanism that Android Auto uses via SharedPreferences.
///
/// Playback is delegated to the live `AudioPlayerPlugin.shared` singleton
/// when the main scene is running. If CarPlay connects before the Flutter
/// scene (cold head-unit connection), the singleton may be nil — in that
/// case we tell the user to open the app on the phone first. Proper
/// background playback from cold connect requires launching a headless
/// AVPlayer inside the scene, which is Phase-3-follow-up work and gated on
/// the entitlement being granted anyway.
@available(iOS 14.0, *)
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        interfaceController.setRootTemplate(buildTabBar(), animated: false) { _, _ in }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        self.interfaceController = nil
    }

    // ------------------------------------------------------------------
    // Template tree
    // ------------------------------------------------------------------

    private func buildTabBar() -> CPTabBarTemplate {
        let favorites = buildStationListTemplate(
            title: "Favorites",
            systemImage: "heart.fill",
            source: { CarPlayLibrary.favorites() }
        )
        let recent = buildStationListTemplate(
            title: "Recent",
            systemImage: "clock.fill",
            source: { CarPlayLibrary.recent() }
        )
        let genres = buildGenresTemplate()
        return CPTabBarTemplate(templates: [favorites, recent, genres])
    }

    private func buildStationListTemplate(
        title: String,
        systemImage: String,
        source: @escaping () -> [CarPlayStation]
    ) -> CPListTemplate {
        let template = CPListTemplate(title: title, sections: [])
        if let image = UIImage(systemName: systemImage) {
            template.tabImage = image
        }
        template.tabTitle = title
        refreshStationList(template, source: source)
        return template
    }

    private func refreshStationList(
        _ template: CPListTemplate,
        source: () -> [CarPlayStation]
    ) {
        let stations = source()
        let items: [CPListItem] = stations.map { station in
            let item = CPListItem(text: station.name, detailText: station.tags)
            item.handler = { [weak self] _, completion in
                self?.playStation(station)
                completion()
            }
            return item
        }
        let section = CPListSection(items: items)
        template.updateSections([section])
    }

    private func buildGenresTemplate() -> CPListTemplate {
        let template = CPListTemplate(title: "Genres", sections: [])
        template.tabImage = UIImage(systemName: "music.note.list")
        template.tabTitle = "Genres"
        let genres = CarPlayLibrary.genres()
        let items: [CPListItem] = genres.map { genre in
            let item = CPListItem(
                text: genre.capitalized,
                detailText: nil
            )
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                self?.pushGenreStations(tag: genre)
                completion()
            }
            return item
        }
        template.updateSections([CPListSection(items: items)])
        return template
    }

    private func pushGenreStations(tag: String) {
        let template = CPListTemplate(title: tag.capitalized, sections: [])
        refreshStationList(template) { CarPlayLibrary.genreStations(tag: tag) }
        interfaceController?.pushTemplate(template, animated: true) { _, _ in }
    }

    // ------------------------------------------------------------------
    // Playback + Now Playing
    // ------------------------------------------------------------------

    private func playStation(_ station: CarPlayStation) {
        // AudioPlayerPlugin.shared holds the live AVPlayer once the Flutter
        // scene has started. Without that, we'd need to spin up our own
        // player inside the CarPlay scene — deferred until entitlement work.
        guard let plugin = AudioPlayerPlugin.shared else { return }
        plugin.playStationFromCarPlay(
            url: station.streamUrl,
            name: station.name,
            favicon: station.favicon
        )
        let nowPlaying = CPNowPlayingTemplate.shared
        interfaceController?.pushTemplate(nowPlaying, animated: true) { _, _ in }
    }
}

// ------------------------------------------------------------------
// Library reads — UserDefaults is the shared store. Populated by Dart
// through AudioPlayerPlugin's sync* method channel calls.
// ------------------------------------------------------------------

struct CarPlayStation {
    let uuid: String
    let name: String
    let streamUrl: String
    let favicon: String?
    let tags: String
}

enum CarPlayLibrary {
    private static let defaults = UserDefaults.standard
    static let keyFavorites = "justradio.favorites"
    static let keyRecent = "justradio.recent"
    static let keyGenres = "justradio.genres"
    static func keyGenreStations(_ tag: String) -> String { "justradio.genre_stations.\(tag)" }

    static func favorites() -> [CarPlayStation] { stations(keyFavorites) }
    static func recent() -> [CarPlayStation] { stations(keyRecent) }
    static func genreStations(tag: String) -> [CarPlayStation] { stations(keyGenreStations(tag)) }

    static func genres() -> [String] {
        guard let data = defaults.data(forKey: keyGenres),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return arr.compactMap { $0["name"] as? String }.filter { !$0.isEmpty }
    }

    private static func stations(_ key: String) -> [CarPlayStation] {
        guard let data = defaults.data(forKey: key),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return arr.compactMap { dict in
            guard
                let uuid = dict["stationuuid"] as? String,
                !uuid.isEmpty,
                let name = dict["name"] as? String,
                let url = dict["streamUrl"] as? String,
                !url.isEmpty
            else { return nil }
            return CarPlayStation(
                uuid: uuid,
                name: name,
                streamUrl: url,
                favicon: (dict["favicon"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                tags: (dict["tags"] as? String) ?? ""
            )
        }
    }
}
