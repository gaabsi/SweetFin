//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

/// SweetFin : les pistes audio et sous-titres proposées dans l'engrenage, et leur nom.
///
/// Les titres des pistes sont ignorés (99 variantes en prod pour dire « français ») :
/// le libellé se calcule depuis la langue et le type (forcé, SDH, audiodescription).
/// Le titre ne sert qu'en secours, quand un drapeau manque.
///
/// Ne touche qu'à l'**affichage** : la piste choisie au lancement reste celle du serveur,
/// et la piste en cours est toujours visible (sinon on ne saurait ni ce qui joue, ni
/// comment en changer).
enum MediaTrackFilter {

    /// Ce que l'utilisateur veut voir dans le menu des sous-titres.
    struct SubtitlePreferences {

        /// Langue préférée (serveur). Sans elle, toutes les langues sont proposées.
        let preferredLanguage: String?
        /// Langues cochées en plus (réglage local).
        let extraLanguages: [String]
        let showSDH: Bool
    }

    private enum Kind {
        case main
        case forced
        case sdh
        case audioDescription
    }

    /// Codes ISO 639-2 « bibliographiques » et leur équivalent « terminologique » : la
    /// même langue a deux codes (`fre` / `fra`), et iOS ne sait normaliser que le second.
    /// Liste figée par la norme.
    private static let terminologicCodes: [String: String] = [
        "alb": "sqi", "arm": "hye", "baq": "eus", "bur": "mya", "chi": "zho",
        "cze": "ces", "dut": "nld", "fre": "fra", "geo": "kat", "ger": "deu",
        "gre": "ell", "ice": "isl", "mac": "mkd", "mao": "mri", "may": "msa",
        "per": "fas", "rum": "ron", "slo": "slk", "tib": "bod", "wel": "cym",
    ]

    // MARK: - Sous-titres

    /// Les sous-titres à proposer, dans l'ordre du fichier.
    ///
    /// Langue préférée + langues cochées (toutes si pas de langue préférée), forcés
    /// toujours, SDH selon le réglage, ni québécois ni commentaire, une seule piste par
    /// langue et par type.
    ///
    /// Parametres :
    /// - streams ([MediaStream]) : les pistes de sous-titres de l'item
    /// - preferences (SubtitlePreferences) : les réglages de l'utilisateur
    /// - selectedIndex (Int?) : index de la piste en cours
    ///
    /// Output :
    /// - streams ([MediaStream]) : les pistes à afficher
    static func visibleSubtitles(
        _ streams: [MediaStream],
        preferences: SubtitlePreferences,
        selectedIndex: Int?
    ) -> [MediaStream] {
        let languages = Set(([preferences.preferredLanguage] + preferences.extraLanguages).compactMap(languageCode))
        let filtersLanguages = languageCode(preferences.preferredLanguage) != nil

        // Filtrer **avant** de dédoublonner : une piste cachée (québécoise) prendrait
        // sinon la place de la piste française de même type.
        let wanted = streams.filter { stream in
            if stream.index == selectedIndex { return true }
            if isQuebec(stream) || isCommentary(stream) { return false }
            if kind(of: stream) == .sdh, !preferences.showSDH { return false }
            if filtersLanguages, !languages.contains(languageCode(stream.language) ?? "") { return false }

            return true
        }
        // En cas de doublon, le texte (SRT) l'emporte sur l'image (PGS) : plus net.
        let priority = { (stream: MediaStream) in (stream.isTextSubtitleStream == true ? 0 : 1, stream.index ?? 0) }
        let textFirst = wanted.sorted { priority($0) < priority($1) }

        return deduplicated(textFirst, selectedIndex: selectedIndex)
    }

    // MARK: - Audio

    /// Les pistes audio à proposer, dans l'ordre du fichier.
    ///
    /// Toutes les langues (il faut pouvoir passer en VO), une piste par langue — celle
    /// qui a le plus de canaux —, audiodescription selon le réglage, pas de commentaire.
    /// Le québécois est caché **sauf** s'il est la seule VF du film.
    ///
    /// Parametres :
    /// - streams ([MediaStream]) : les pistes audio de l'item
    /// - showAudioDescription (Bool) : réglage de l'utilisateur
    /// - selectedIndex (Int?) : index de la piste en cours
    ///
    /// Output :
    /// - streams ([MediaStream]) : les pistes à afficher
    static func visibleAudio(
        _ streams: [MediaStream],
        showAudioDescription: Bool,
        selectedIndex: Int?
    ) -> [MediaStream] {
        let wanted = streams.filter { stream in
            if stream.index == selectedIndex { return true }
            if isCommentary(stream) { return false }
            if kind(of: stream) == .audioDescription { return showAudioDescription }
            if isQuebec(stream) { return !hasStandardTrack(in: streams, language: languageCode(stream.language)) }

            return true
        }
        let byChannels = wanted.sorted { ($0.channels ?? 0) > ($1.channels ?? 0) }

        return deduplicated(byChannels, selectedIndex: selectedIndex)
    }

    // MARK: - Libellés

    /// « Français », « Français (forcé) », « Anglais (SDH) », « Audio 2 ».
    ///
    /// Parametres :
    /// - stream (MediaStream) : la piste
    /// - streams ([MediaStream]) : toutes les pistes du même type, pour numéroter une
    ///   piste sans langue
    ///
    /// Output :
    /// - label (String) : le libellé du menu
    static func label(of stream: MediaStream, among streams: [MediaStream]) -> String {
        guard let language = languageName(stream.language) else {
            let position = (streams.firstIndex { $0.index == stream.index } ?? 0) + 1
            return PlayerStrings.untitledTrack(isAudio: stream.type == .audio, position: position)
        }

        switch kind(of: stream) {
        case .main:
            return language
        case .forced:
            return PlayerStrings.forcedTrack(language)
        case .sdh:
            return PlayerStrings.sdhTrack(language)
        case .audioDescription:
            return PlayerStrings.audioDescriptionTrack(language)
        }
    }

    /// Le nom d'une langue dans celle de l'appareil (`fre` → « Français »).
    ///
    /// Parametres :
    /// - code (String?) : code ISO 639-1 ou 639-2
    ///
    /// Output :
    /// - name (String?) : le nom, nil si la langue est absente ou inconnue
    static func languageName(_ code: String?) -> String? {
        languageCode(code)
            .flatMap { Locale.current.localizedString(forLanguageCode: $0) }?
            .capitalized(with: .current)
    }

    /// Code de langue normalisé en deux lettres (`fre`, `fra`, `fr` → `fr`), pour
    /// comparer les pistes et les réglages quelle que soit la norme employée.
    ///
    /// Parametres :
    /// - code (String?) : code ISO 639-1 ou 639-2
    ///
    /// Output :
    /// - code (String?) : code normalisé, nil si absent ou indéterminé (`und`)
    static func languageCode(_ code: String?) -> String? {
        guard let code = code?.lowercased(), code.isNotEmpty, code != "und" else { return nil }
        let terminologic = terminologicCodes[code] ?? code

        return Locale.Language(identifier: terminologic).languageCode?.identifier ?? terminologic
    }

    // MARK: - Règles

    /// Une seule piste par langue et par type, la première de la liste reçue ; la piste
    /// en cours prend la place de son doublon. Les pistes sans langue ne sont jamais
    /// fusionnées entre elles : rien ne dit qu'elles sont identiques.
    private static func deduplicated(_ streams: [MediaStream], selectedIndex: Int?) -> [MediaStream] {
        let selectedFirst = streams.filter { $0.index == selectedIndex } + streams.filter { $0.index != selectedIndex }
        var seen: Set<String> = []

        return selectedFirst
            .filter { stream in
                let language = languageCode(stream.language) ?? "#\(stream.index ?? 0)"
                return seen.insert("\(language)|\(kind(of: stream))").inserted
            }
            .sorted { ($0.index ?? 0) < ($1.index ?? 0) }
    }

    /// Vrai s'il existe une piste ordinaire (ni québécoise, ni audiodescription) dans
    /// cette langue.
    private static func hasStandardTrack(in streams: [MediaStream], language: String?) -> Bool {
        streams.contains { stream in
            languageCode(stream.language) == language && !isQuebec(stream) && kind(of: stream) == .main
        }
    }

    /// Le type de la piste. Le drapeau d'abord, le titre en secours : certaines pistes
    /// ne le disent que là (« FR Forced », « VO - SDH », « VFF AD »).
    private static func kind(of stream: MediaStream) -> Kind {
        let title = stream.title?.lowercased() ?? ""
        let words = titleWords(of: stream)

        if stream.type == .audio {
            let isDescribed = words.contains("ad") || title.contains("descri") || title.contains("malvoy")
            return isDescribed ? .audioDescription : .main
        }

        if stream.isForced == true || title.contains("forc") { return .forced }
        if stream.isHearingImpaired == true || words.contains("sdh") || words.contains("cc") { return .sdh }

        return .main
    }

    /// Le français du Québec, tagué `fre` comme celui de France : seul le titre le dit.
    private static func isQuebec(_ stream: MediaStream) -> Bool {
        let title = stream.title?.lowercased() ?? ""

        return titleWords(of: stream).contains("vfq") || ["canad", "québ", "quebec"].contains { title.contains($0) }
    }

    private static func isCommentary(_ stream: MediaStream) -> Bool {
        stream.title?.lowercased().contains("comment") ?? false
    }

    /// Les mots du titre, pour chercher un sigle court (« AD », « CC ») sans le trouver
    /// au milieu d'un autre mot.
    private static func titleWords(of stream: MediaStream) -> Set<String> {
        let title = stream.title?.lowercased() ?? ""

        return Set(title.split { !$0.isLetter }.map(String.init))
    }
}
