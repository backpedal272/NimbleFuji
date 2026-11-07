import Foundation

/// Recipes written to the recipes folder the first time the app runs.
nonisolated enum SampleRecipes {
    static let yaml: [String] = [
        """
        name: CLAUTRA 800
        film_simulation: Classic Chrome
        grain: Strong Large
        color_chrome_effect: Weak
        color_chrome_fx_blue: "Off"
        white_balance: 6300K
        wb_shift_red: 1
        wb_shift_blue: -3
        dynamic_range: DR400
        highlight: -1.5
        shadow: -0.5
        color: 2
        sharpness: -2
        high_iso_nr: -4
        clarity: -2
        smooth_skin: "Off"
        source: https://www.aiformortals.co/blog/claude-code-control-fujifilm-camera
        notes: Warm Portra-style look built from a Portra 800 v3 starting point.
        """,
        """
        name: Faithful Provia
        film_simulation: Provia
        grain: "Off"
        color_chrome_effect: "Off"
        color_chrome_fx_blue: "Off"
        white_balance: As Shot
        dynamic_range: DR200
        highlight: 0
        shadow: 0
        color: 0
        sharpness: 0
        high_iso_nr: -2
        clarity: 0
        notes: A neutral baseline, handy for comparing against other recipes.
        """,
        """
        name: Street Acros
        film_simulation: Acros + R
        grain: Weak Small
        white_balance: Auto
        dynamic_range: DR200
        highlight: 0.5
        shadow: 1.5
        sharpness: 1
        high_iso_nr: -4
        clarity: 2
        notes: Punchy black and white with a red filter for darker skies.
        """,
    ]
}
