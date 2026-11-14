// swift tools/winshot.swift <owner> <out.png> - capture that app's main window by id (no input sent anywhere)
import CoreGraphics
import Foundation
let owner = CommandLine.arguments[1], out = CommandLine.arguments[2]
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
let w = list.filter { ($0[kCGWindowOwnerName as String] as? String) == owner && ($0[kCGWindowLayer as String] as? Int) == 0 }
    .filter { (($0[kCGWindowBounds as String] as? [String: Double])?["Height"] ?? 0) > 300 }.first
guard let id = w?[kCGWindowNumber as String] as? Int else { exit(1) }
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); p.arguments = ["-x", "-o", "-l", "\(id)", out]
try p.run(); p.waitUntilExit()
