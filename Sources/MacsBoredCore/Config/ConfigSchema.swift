import Foundation

/// The JSON Schema written beside `config.json` as `config.schema.json`, so editors and agents can
/// check a change before saving it. Kept in step with `ConfigFile` by `ConfigSchemaTests`.
public enum ConfigSchema {
    public static let text = #"""
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "MacsBored settings",
  "description": "MacsBored's settings file. MacsBored watches it: a valid change applies within a second; a file with a mistake is left alone, the last good settings keep running and the menu bar names the line. Fields MacsBored doesn't know are kept. Check a file with: macsbored check",
  "type": "object",
  "properties": {
    "$schema": {
      "type": "string"
    },
    "enabled": {
      "type": "boolean",
      "default": true,
      "description": "The main switch for passthrough."
    },
    "openAtLogin": {
      "type": "boolean",
      "description": "Open MacsBored when you log in. Leave it out to keep macOS's current setting."
    },
    "pauseKeys": {
      "oneOf": [
        {
          "$ref": "#/$defs/keys"
        },
        {
          "type": "null"
        }
      ],
      "default": "ctrl+opt+cmd+P",
      "description": "Pauses passthrough inside a passthrough app until you switch apps. null for none."
    },
    "capsLockAsHyper": {
      "type": "boolean",
      "default": false,
      "description": "Caps Lock holds ctrl+opt+shift+cmd (hyper), for triggers of your own."
    },
    "passthrough": {
      "type": "array",
      "description": "Apps that get macOS's own shortcuts while they're in front: remote desktops and virtual machines. The first entry that fits wins.",
      "items": {
        "$ref": "#/$defs/passthrough"
      }
    },
    "triggers": {
      "type": "array",
      "description": "Keys of your own that do one thing.",
      "items": {
        "$ref": "#/$defs/trigger"
      }
    },
    "setupCompleted": {
      "type": "boolean",
      "default": false,
      "description": "Whether first-time setup has been done; false shows it at launch."
    }
  },
  "$defs": {
    "keys": {
      "type": "string",
      "description": "Keys as text: modifiers then the key, joined by +. Modifiers: ctrl, opt (or alt), shift, cmd, or hyper for all four. Keys: A–Z, 0–9, punctuation, space, tab, return, escape, delete, left, right, up, down, home, end, pageup, pagedown, F1–F20. The menu's symbols (⌃⌥⇧⌘) also work.",
      "examples": [
        "ctrl+opt+cmd+P",
        "hyper+N",
        "cmd+space",
        "shift+cmd+4",
        "F13"
      ]
    },
    "app": {
      "type": "string",
      "description": "An app by its bundle ID. Find one with: osascript -e 'id of app \"Notes\"'",
      "examples": [
        "com.microsoft.rdc.macos",
        "com.apple.Notes"
      ]
    },
    "condition": {
      "type": "object",
      "description": "One condition: {\"if\": kind} must hold, {\"unless\": kind} must not. windowTitleContains takes \"text\"; timeBetween takes \"from\" and \"to\" (a range past midnight wraps).",
      "properties": {
        "if": {
          "enum": [
            "fullScreen",
            "fillsScreen",
            "windowTitleContains",
            "externalDisplay",
            "onBattery",
            "timeBetween",
            "capsLock"
          ]
        },
        "unless": {
          "enum": [
            "fullScreen",
            "fillsScreen",
            "windowTitleContains",
            "externalDisplay",
            "onBattery",
            "timeBetween",
            "capsLock"
          ]
        },
        "text": {
          "type": "string"
        },
        "from": {
          "type": "string",
          "pattern": "^([01][0-9]|2[0-3]):[0-5][0-9]$",
          "examples": [
            "09:00",
            "17:30"
          ]
        },
        "to": {
          "type": "string",
          "pattern": "^([01][0-9]|2[0-3]):[0-5][0-9]$",
          "examples": [
            "09:00",
            "17:30"
          ]
        }
      },
      "oneOf": [
        {
          "required": [
            "if"
          ]
        },
        {
          "required": [
            "unless"
          ]
        }
      ],
      "examples": [
        {
          "if": "fullScreen"
        },
        {
          "unless": "onBattery"
        },
        {
          "if": "windowTitleContains",
          "text": "Prod"
        },
        {
          "if": "timeBetween",
          "from": "09:00",
          "to": "17:30"
        }
      ]
    },
    "when": {
      "description": "When it acts. A list means all of them must hold; {\"any\": [...]} means any one. Leave it out for always.",
      "oneOf": [
        {
          "type": "array",
          "items": {
            "$ref": "#/$defs/condition"
          }
        },
        {
          "type": "object",
          "properties": {
            "all": {
              "type": "array",
              "items": {
                "$ref": "#/$defs/condition"
              }
            }
          },
          "required": [
            "all"
          ],
          "additionalProperties": false
        },
        {
          "type": "object",
          "properties": {
            "any": {
              "type": "array",
              "items": {
                "$ref": "#/$defs/condition"
              }
            }
          },
          "required": [
            "any"
          ],
          "additionalProperties": false
        }
      ]
    },
    "action": {
      "type": "object",
      "description": "Exactly one of these.",
      "minProperties": 1,
      "maxProperties": 1,
      "properties": {
        "sendKeys": {
          "$ref": "#/$defs/keys",
          "description": "Press these keys instead."
        },
        "openApp": {
          "$ref": "#/$defs/app",
          "description": "Open this app, or bring it to the front."
        },
        "runShortcut": {
          "type": "string",
          "description": "Run the Shortcut with this name in Apple's Shortcuts app."
        },
        "passThrough": {
          "const": true,
          "description": "Send the trigger's own keys straight to the app in front, ahead of macOS and other apps' global shortcuts."
        },
        "open": {
          "type": "string",
          "description": "Open a link, or a file or folder (~/ works)."
        }
      },
      "additionalProperties": false,
      "examples": [
        {
          "openApp": "com.apple.Notes"
        },
        {
          "runShortcut": "Start a Focus timer"
        },
        {
          "sendKeys": "cmd+left"
        },
        {
          "passThrough": true
        },
        {
          "open": "https://example.com"
        }
      ]
    },
    "passthrough": {
      "type": "object",
      "required": [
        "apps"
      ],
      "properties": {
        "name": {
          "type": "string",
          "description": "Defaults to the first app's name."
        },
        "enabled": {
          "type": "boolean",
          "default": true
        },
        "apps": {
          "type": "array",
          "minItems": 1,
          "items": {
            "$ref": "#/$defs/app"
          }
        },
        "shortcuts": {
          "description": "Which groups of macOS shortcuts the app gets, or \"all\". Defaults to every group but accessibility.",
          "oneOf": [
            {
              "type": "array",
              "items": {
                "enum": [
                  "appSwitcher",
                  "spotlight",
                  "missionControl",
                  "spaces",
                  "screenshots",
                  "inputSources",
                  "dockAndCentre",
                  "keyboardNavigation",
                  "accessibility",
                  "helpMenu"
                ]
              },
              "uniqueItems": true
            },
            {
              "const": "all"
            }
          ]
        },
        "sendEveryKey": {
          "type": "boolean",
          "default": false,
          "description": "Send every key straight to the app, ahead of other apps' global shortcuts (Raycast, Alfred, window managers)."
        },
        "modifiers": {
          "enum": [
            "asIs",
            "swapCommandControl"
          ],
          "default": "asIs",
          "description": "asIs: as the app maps them. swapCommandControl: cmd acts as Ctrl and ctrl as the Windows key."
        },
        "when": {
          "$ref": "#/$defs/when"
        }
      },
      "examples": [
        {
          "name": "Windows App",
          "apps": [
            "com.microsoft.rdc.macos"
          ],
          "shortcuts": [
            "appSwitcher",
            "spotlight",
            "missionControl",
            "spaces",
            "screenshots"
          ]
        }
      ]
    },
    "trigger": {
      "type": "object",
      "required": [
        "action"
      ],
      "properties": {
        "name": {
          "type": "string"
        },
        "keys": {
          "oneOf": [
            {
              "$ref": "#/$defs/keys"
            },
            {
              "type": "array",
              "items": {
                "$ref": "#/$defs/keys"
              },
              "uniqueItems": true
            },
            {
              "type": "null"
            }
          ],
          "description": "The keys that set it off: one, or a list where any of them does. Each needs cmd, ctrl or opt (or an F-key). null: the trigger does nothing until it has keys.",
          "examples": [
            "ctrl+opt+N",
            [
              "cmd+space",
              "cmd+tab"
            ]
          ]
        },
        "enabled": {
          "type": "boolean",
          "default": true
        },
        "action": {
          "$ref": "#/$defs/action"
        },
        "apps": {
          "type": "array",
          "items": {
            "$ref": "#/$defs/app"
          },
          "description": "Only in these apps. Leave it out for everywhere except passthrough apps."
        },
        "when": {
          "$ref": "#/$defs/when"
        }
      },
      "examples": [
        {
          "name": "Open Notes",
          "keys": "ctrl+opt+N",
          "action": {
            "openApp": "com.apple.Notes"
          }
        }
      ]
    }
  }
}
"""#
}
