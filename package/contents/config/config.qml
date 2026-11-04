// SPDX-FileCopyrightText: 2026 Jeff
// SPDX-License-Identifier: MIT

import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "preferences-other"
        source: "configGeneral.qml"
    }
}
