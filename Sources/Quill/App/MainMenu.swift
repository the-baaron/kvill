import AppKit

/// Builds the menu bar in code. Quill has no nib, so this is the single place
/// that defines every command and its key equivalent.
enum MainMenu {

    static func build(appDelegate: AppDelegate) -> NSMenu {
        let main = NSMenu()
        main.addItem(appMenu())
        main.addItem(fileMenu())
        main.addItem(editMenu())
        main.addItem(formatMenu())
        main.addItem(viewMenu(appDelegate: appDelegate))
        main.addItem(windowMenu())
        main.addItem(helpMenu())
        return main
    }

    // MARK: - Builders

    private static func submenu(_ title: String, _ build: (NSMenu) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        build(menu)
        item.submenu = menu
        return item
    }

    @discardableResult
    private static func add(
        _ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
        modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil,
        represented: Any? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.target = target
        item.representedObject = represented
        menu.addItem(item)
        return item
    }

    // MARK: - Application

    private static func appMenu() -> NSMenuItem {
        submenu("Quill") { menu in
            add(menu, "About Quill", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
            menu.addItem(.separator())
            add(menu, "Settings…", #selector(DocumentViewController.toggleThemePanel(_:)), ",")
            menu.addItem(.separator())
            add(menu, "Make Quill the Default Markdown Editor…",
                #selector(AppDelegate.setAsDefaultMarkdownEditor(_:)))
            menu.addItem(.separator())

            let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
            let servicesMenu = NSMenu(title: "Services")
            services.submenu = servicesMenu
            NSApp.servicesMenu = servicesMenu
            menu.addItem(services)
            menu.addItem(.separator())

            add(menu, "Hide Quill", #selector(NSApplication.hide(_:)), "h")
            add(menu, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h",
                modifiers: [.command, .option])
            add(menu, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
            menu.addItem(.separator())
            add(menu, "Quit Quill", #selector(NSApplication.terminate(_:)), "q")
        }
    }

    // MARK: - File

    private static func fileMenu() -> NSMenuItem {
        submenu("File") { menu in
            add(menu, "New", #selector(NSDocumentController.newDocument(_:)), "n")
            add(menu, "Open…", #selector(NSDocumentController.openDocument(_:)), "o")

            let recent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
            let recentMenu = NSMenu(title: "Open Recent")
            let clear = NSMenuItem(
                title: "Clear Menu",
                action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
            recentMenu.addItem(clear)
            // AppKit fills this menu itself once it is identified by name.
            recentMenu.identifier = NSUserInterfaceItemIdentifier("NSRecentDocumentsMenu")
            recent.submenu = recentMenu
            menu.addItem(recent)

            menu.addItem(.separator())
            add(menu, "Close", #selector(NSWindow.performClose(_:)), "w")
            add(menu, "Save…", #selector(NSDocument.save(_:)), "s")
            add(menu, "Save As…", #selector(NSDocument.saveAs(_:)), "s", modifiers: [.command, .shift])
            add(menu, "Revert to Saved", #selector(NSDocument.revertToSaved(_:)))
            menu.addItem(.separator())
            add(menu, "Page Setup…", #selector(NSDocument.runPageLayout(_:)), "p",
                modifiers: [.command, .shift])
            add(menu, "Print…", #selector(NSDocument.printDocument(_:)), "p")
        }
    }

    // MARK: - Edit

    private static func editMenu() -> NSMenuItem {
        submenu("Edit") { menu in
            add(menu, "Undo", Selector(("undo:")), "z")
            add(menu, "Redo", Selector(("redo:")), "z", modifiers: [.command, .shift])
            menu.addItem(.separator())
            add(menu, "Cut", #selector(NSText.cut(_:)), "x")
            add(menu, "Copy", #selector(NSText.copy(_:)), "c")
            add(menu, "Paste", #selector(NSText.paste(_:)), "v")
            add(menu, "Paste and Match Style",
                #selector(NSTextView.pasteAsPlainText(_:)), "v", modifiers: [.command, .option, .shift])
            add(menu, "Delete", #selector(NSText.delete(_:)))
            add(menu, "Select All", #selector(NSText.selectAll(_:)), "a")
            menu.addItem(.separator())

            menu.addItem(submenu("Find") { find in
                let item = add(find, "Find…", #selector(NSTextView.performTextFinderAction(_:)), "f")
                item.tag = NSTextFinder.Action.showFindInterface.rawValue

                let next = add(find, "Find Next", #selector(NSTextView.performTextFinderAction(_:)), "g")
                next.tag = NSTextFinder.Action.nextMatch.rawValue

                let previous = add(
                    find, "Find Previous", #selector(NSTextView.performTextFinderAction(_:)), "g",
                    modifiers: [.command, .shift])
                previous.tag = NSTextFinder.Action.previousMatch.rawValue

                let useSelection = add(
                    find, "Use Selection for Find", #selector(NSTextView.performTextFinderAction(_:)), "e")
                useSelection.tag = NSTextFinder.Action.setSearchString.rawValue

                let replace = add(
                    find, "Find and Replace…", #selector(NSTextView.performTextFinderAction(_:)), "f",
                    modifiers: [.command, .option])
                replace.tag = NSTextFinder.Action.showReplaceInterface.rawValue
            })

            menu.addItem(submenu("Spelling") { spelling in
                add(spelling, "Show Spelling and Grammar",
                    #selector(NSText.showGuessPanel(_:)), ":")
                add(spelling, "Check Document Now", #selector(NSText.checkSpelling(_:)), ";")
                spelling.addItem(.separator())
                add(spelling, "Check Spelling While Typing",
                    #selector(NSTextView.toggleContinuousSpellChecking(_:)))
            })

            menu.addItem(submenu("Substitutions") { substitutions in
                add(substitutions, "Smart Quotes",
                    #selector(NSTextView.toggleAutomaticQuoteSubstitution(_:)))
                add(substitutions, "Smart Dashes",
                    #selector(NSTextView.toggleAutomaticDashSubstitution(_:)))
                add(substitutions, "Text Replacement",
                    #selector(NSTextView.toggleAutomaticTextReplacement(_:)))
            })

            menu.addItem(.separator())
            add(menu, "Emoji & Symbols", #selector(NSApplication.orderFrontCharacterPalette(_:)), " ",
                modifiers: [.command, .control])
        }
    }

    // MARK: - Format

    private static func formatMenu() -> NSMenuItem {
        submenu("Format") { menu in
            add(menu, "Bold", #selector(EditorViewController.toggleBold(_:)), "b")
            add(menu, "Italic", #selector(EditorViewController.toggleItalic(_:)), "i")
            add(menu, "Strikethrough", #selector(EditorViewController.toggleStrikethrough(_:)), "s",
                modifiers: [.command, .control])
            add(menu, "Highlight", #selector(EditorViewController.toggleHighlight(_:)), "h",
                modifiers: [.command, .control])
            add(menu, "Inline Code", #selector(EditorViewController.toggleInlineCode(_:)), "c",
                modifiers: [.command, .control])
            add(menu, "Inline Math", #selector(EditorViewController.toggleMath(_:)), "m",
                modifiers: [.command, .control])
            menu.addItem(.separator())

            add(menu, "Link…", #selector(EditorViewController.insertLink(_:)), "k")
            add(menu, "Image…", #selector(EditorViewController.insertImage(_:)), "k",
                modifiers: [.command, .shift])
            add(menu, "Footnote", #selector(EditorViewController.insertFootnote(_:)))
            menu.addItem(.separator())

            menu.addItem(submenu("Heading") { headings in
                add(headings, "Heading 1", #selector(EditorViewController.setHeading1(_:)), "1")
                add(headings, "Heading 2", #selector(EditorViewController.setHeading2(_:)), "2")
                add(headings, "Heading 3", #selector(EditorViewController.setHeading3(_:)), "3")
                add(headings, "Heading 4", #selector(EditorViewController.setHeading4(_:)), "4")
                add(headings, "Heading 5", #selector(EditorViewController.setHeading5(_:)), "5")
                add(headings, "Heading 6", #selector(EditorViewController.setHeading6(_:)), "6")
                headings.addItem(.separator())
                add(headings, "Body Text", #selector(EditorViewController.setBodyText(_:)), "0")
            })

            menu.addItem(submenu("List") { list in
                add(list, "Bulleted List", #selector(EditorViewController.toggleBulletList(_:)), "8",
                    modifiers: [.command, .shift])
                add(list, "Numbered List", #selector(EditorViewController.toggleNumberedList(_:)), "7",
                    modifiers: [.command, .shift])
                add(list, "Task List", #selector(EditorViewController.toggleTaskList(_:)), "9",
                    modifiers: [.command, .shift])
            })

            menu.addItem(submenu("Callout") { callouts in
                add(callouts, "Note", #selector(EditorViewController.insertCalloutNote(_:)))
                add(callouts, "Tip", #selector(EditorViewController.insertCalloutTip(_:)))
                add(callouts, "Important", #selector(EditorViewController.insertCalloutImportant(_:)))
                add(callouts, "Warning", #selector(EditorViewController.insertCalloutWarning(_:)))
                add(callouts, "Caution", #selector(EditorViewController.insertCalloutCaution(_:)))
            })

            menu.addItem(.separator())
            add(menu, "Blockquote", #selector(EditorViewController.toggleBlockquote(_:)), "'")
            add(menu, "Code Block", #selector(EditorViewController.insertCodeBlock(_:)), "c",
                modifiers: [.command, .shift])
            add(menu, "Table", #selector(EditorViewController.insertTable(_:)), "t",
                modifiers: [.command, .control])
            add(menu, "Horizontal Rule", #selector(EditorViewController.insertHorizontalRule(_:)), "-",
                modifiers: [.command, .shift])
        }
    }

    // MARK: - View

    private static func viewMenu(appDelegate: AppDelegate) -> NSMenuItem {
        submenu("View") { menu in
            menu.addItem(submenu("Theme") { themes in
                let follow = add(
                    themes, "Follow System Appearance",
                    #selector(AppDelegate.toggleFollowSystem(_:)), target: appDelegate)
                follow.tag = MenuTag.followSystem
                themes.addItem(.separator())
                for palette in Palettes.all {
                    let item = add(
                        themes, palette.name, #selector(AppDelegate.selectPalette(_:)),
                        target: appDelegate, represented: palette.id)
                    item.tag = MenuTag.palette
                }
                themes.addItem(.separator())
                add(themes, "Next Theme", #selector(AppDelegate.cyclePalette(_:)), "]",
                    modifiers: [.command, .control], target: appDelegate)
            })

            menu.addItem(submenu("Typography") { typography in
                for preset in TypographyPreset.all {
                    let item = add(
                        typography, preset.name, #selector(AppDelegate.selectPreset(_:)),
                        target: appDelegate, represented: preset.id)
                    item.tag = MenuTag.preset
                }
                typography.addItem(.separator())
                add(typography, "Next Typography", #selector(AppDelegate.cyclePreset(_:)), "[",
                    modifiers: [.command, .control], target: appDelegate)
            })

            menu.addItem(submenu("Text Size") { size in
                add(size, "Bigger", #selector(AppDelegate.increaseTextSize(_:)), "+", target: appDelegate)
                add(size, "Smaller", #selector(AppDelegate.decreaseTextSize(_:)), "-", target: appDelegate)
                add(size, "Default", #selector(AppDelegate.resetTextSize(_:)), "0",
                    modifiers: [.command, .option], target: appDelegate)
                size.addItem(.separator())
                for value in TextSize.allCases {
                    let item = add(
                        size, value.name, #selector(AppDelegate.selectTextSize(_:)),
                        target: appDelegate, represented: value.rawValue)
                    item.tag = MenuTag.textSize
                }
            })

            menu.addItem(submenu("Line Width") { width in
                for value in LineWidth.allCases {
                    let item = add(
                        width, value.name, #selector(AppDelegate.selectLineWidth(_:)),
                        target: appDelegate, represented: value.rawValue)
                    item.tag = MenuTag.lineWidth
                }
            })

            menu.addItem(.separator())
            let focus = add(
                menu, "Focus Mode", #selector(AppDelegate.toggleFocusMode(_:)), "f",
                modifiers: [.command, .shift], target: appDelegate)
            focus.tag = MenuTag.focusMode

            let typewriter = add(
                menu, "Typewriter Scrolling", #selector(AppDelegate.toggleTypewriter(_:)), "y",
                modifiers: [.command, .shift], target: appDelegate)
            typewriter.tag = MenuTag.typewriter

            let markers = add(
                menu, "Always Show Syntax Markers", #selector(AppDelegate.toggleMarkers(_:)), "m",
                modifiers: [.command, .shift], target: appDelegate)
            markers.tag = MenuTag.markers

            menu.addItem(.separator())
            add(menu, "Settings Panel", #selector(DocumentViewController.toggleThemePanel(_:)), "t")
            add(menu, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f",
                modifiers: [.command, .control])
        }
    }

    // MARK: - Window and Help

    private static func windowMenu() -> NSMenuItem {
        let item = submenu("Window") { menu in
            add(menu, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
            add(menu, "Zoom", #selector(NSWindow.performZoom(_:)))
            menu.addItem(.separator())
            add(menu, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        }
        NSApp.windowsMenu = item.submenu
        return item
    }

    private static func helpMenu() -> NSMenuItem {
        let item = submenu("Help") { menu in
            add(menu, "Quill Markdown Reference",
                #selector(AppDelegate.openCheatSheet(_:)), "?", target: NSApp.delegate as AnyObject)
        }
        NSApp.helpMenu = item.submenu
        return item
    }
}

/// Tags let one `validateMenuItem` implementation tick the right boxes.
enum MenuTag {
    static let palette = 1001
    static let preset = 1002
    static let textSize = 1003
    static let lineWidth = 1004
    static let focusMode = 1005
    static let typewriter = 1006
    static let markers = 1007
    static let followSystem = 1008
}
