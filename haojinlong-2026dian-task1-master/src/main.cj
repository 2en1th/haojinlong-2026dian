package svg_renderer

import std.collection.*
import std.convert.*
import std.fs.*
import std.math.*
import std.sort.*

func readAllText(path: String): String {
    let f = File(path, OpenMode.Read)
    let buf = Array<Byte>(65536, {_ => UInt8(0)})
    var bytes = ArrayList<Byte>()
    var n = f.read(buf)
    while (n > 0) {
        var i: Int64 = 0
        while (i < n) { bytes.add(buf[i]); i++ }
        n = f.read(buf)
    }
    f.close()
    var runes = ArrayList<Rune>()
    for (b in bytes) {
        if (b >= UInt8(32) || b == UInt8(10) || b == UInt8(13) || b == UInt8(9)) {
            runes.add(Rune(b))
        }
    }
    return String(runes.toArray())
}

func parseColor(s: String): (Byte, Byte, Byte) {
    if (s.size > 0 && s[0] == UInt8(35)) {
        let hex = s[1..]
        if (hex.size >= 6) {
            let r = Int64.parse(hex[0..2], radix: 16)
            let g = Int64.parse(hex[2..4], radix: 16)
            let b = Int64.parse(hex[4..6], radix: 16)
            return (UInt8(r & 0xFF), UInt8(g & 0xFF), UInt8(b & 0xFF))
        }
    }
    return (UInt8(0), UInt8(0), UInt8(0))
}

struct Point {
    var x: Float64 = 0.0
    var y: Float64 = 0.0
    init(x_: Float64, y_: Float64) { x = x_; y = y_ }
}

struct Transform {
    var tx: Float64 = 0.0
    var ty: Float64 = 0.0
    var sx: Float64 = 1.0
    var sy: Float64 = 1.0
    init() { tx = 0.0; ty = 0.0; sx = 1.0; sy = 1.0 }
    init(tx_: Float64, ty_: Float64, sx_: Float64, sy_: Float64) {
        tx = tx_; ty = ty_; sx = sx_; sy = sy_
    }
    func apply(p: Point): Point {
        return Point(p.x * sx + tx, p.y * sy + ty)
    }
}

func cubicBez(p0: Float64, p1: Float64, p2: Float64, p3: Float64, t: Float64): Float64 {
    let mt = 1.0 - t
    return mt*mt*mt*p0 + 3.0*mt*mt*t*p1 + 3.0*mt*t*t*p2 + t*t*t*p3
}

func quadBez(p0: Float64, p1: Float64, p2: Float64, t: Float64): Float64 {
    let mt = 1.0 - t
    return mt*mt*p0 + 2.0*mt*t*p1 + t*t*p2
}

func isLetter(c: UInt8): Bool {
    return (c >= UInt8(65) && c <= UInt8(90)) || (c >= UInt8(97) && c <= UInt8(122))
}

func isWS(c: UInt8): Bool {
    return c == UInt8(32) || c == UInt8(44) || c == UInt8(9) || c == UInt8(10) || c == UInt8(13)
}

func readTokNum(data: String, pos: Int64): (Float64, Int64) {
    var p = pos
    while (p < data.size && isWS(data[p])) { p++ }
    var start = p
    if (p < data.size && (data[p] == UInt8(43) || data[p] == UInt8(45))) { p++ }
    var hd = false; var he = false
    while (p < data.size) {
        let c = data[p]
        if (c >= UInt8(48) && c <= UInt8(57)) { p++ }
        else if (c == UInt8(46) && !hd) { hd = true; p++ }
        else if ((c == UInt8(101) || c == UInt8(69)) && !he) {
            he = true; p++
            if (p < data.size && (data[p] == UInt8(43) || data[p] == UInt8(45))) { p++ }
        }
        else { break }
    }
    if (p == start) { return (0.0, p) }
    return (Float64.parse(data[start..p]), p)
}

func strIdx(s: String, sub: String, start: Int64): Int64 {
    match (s.indexOf(sub, start)) {
        case Some(v) => return Int64(v)
        case None => return -1
    }
}

func strIdx1(s: String, sub: String): Int64 {
    match (s.indexOf(sub)) {
        case Some(v) => return Int64(v)
        case None => return -1
    }
}

func skipWS(d: String, pos: Int64): Int64 {
    var p = pos
    while (p < d.size && isWS(d[p])) { p++ }
    return p
}

func atPathEnd(d: String, pos: Int64): Bool {
    var p = skipWS(d, pos)
    return p >= d.size || isLetter(d[p])
}

func rectToPathD(x: Float64, y: Float64, w: Float64, h: Float64): String {
    return "M${x} ${y} L${x + w} ${y} L${x + w} ${y + h} L${x} ${y + h} Z"
}

func circleToPathD(cx: Float64, cy: Float64, r: Float64): String {
    var d = ""
    var i: Int64 = 0
    let segs = 64
    while (i < segs) {
        let a1 = 2.0 * 3.14159265358979 * Float64(i) / Float64(segs)
        let a2 = 2.0 * 3.14159265358979 * Float64(i + 1) / Float64(segs)
        let x1 = cx + r * cos(a1)
        let y1 = cy + r * sin(a1)
        let x2 = cx + r * cos(a2)
        let y2 = cy + r * sin(a2)
        if (i == 0) { d = "M${x1} ${y1}" }
        d = d + " L${x2} ${y2}"
        i++
    }
    d = d + " Z"
    return d
}

func ellipseToPathD(cx: Float64, cy: Float64, rx: Float64, ry: Float64): String {
    var d = ""
    var i: Int64 = 0
    let segs = 64
    while (i < segs) {
        let a1 = 2.0 * 3.14159265358979 * Float64(i) / Float64(segs)
        let a2 = 2.0 * 3.14159265358979 * Float64(i + 1) / Float64(segs)
        let x1 = cx + rx * cos(a1)
        let y1 = cy + ry * sin(a1)
        let x2 = cx + rx * cos(a2)
        let y2 = cy + ry * sin(a2)
        if (i == 0) { d = "M${x1} ${y1}" }
        d = d + " L${x2} ${y2}"
        i++
    }
    d = d + " Z"
    return d
}

func flattenPath(d: String): ArrayList<ArrayList<Point>> {
    let subpaths = ArrayList<ArrayList<Point>>()
    var current = ArrayList<Point>()
    var pos: Int64 = 0
    var cx = 0.0; var cy = 0.0; var startX = 0.0; var startY = 0.0
    var lastCX = 0.0; var lastCY = 0.0; var lastCX2 = 0.0; var lastCY2 = 0.0
    var lastCmd: Int64 = 0
    let steps = 64
    var needNewSub = false

    while (pos < d.size) {
        pos = skipWS(d, pos)
        if (pos >= d.size) { break }
        var cmdVal: Int64 = 0
        if (isLetter(d[pos])) {
            cmdVal = Int64(d[pos])
            pos++
        } else {
            cmdVal = lastCmd
        }

        if (cmdVal == 77) { // M
            if (needNewSub && current.size > 0) {
                subpaths.add(current)
                current = ArrayList<Point>()
            }
            needNewSub = true
            var (x, n1) = readTokNum(d, pos); pos = n1
            var (y, n2) = readTokNum(d, pos); pos = n2
            cx = x; cy = y; startX = x; startY = y
            current.add(Point(x, y))
            while (!atPathEnd(d, pos)) {
                (x, n1) = readTokNum(d, pos); pos = n1
                (y, n2) = readTokNum(d, pos); pos = n2
                cx = x; cy = y; current.add(Point(x, y))
            }
        } else if (cmdVal == 109) { // m
            if (needNewSub && current.size > 0) {
                subpaths.add(current)
                current = ArrayList<Point>()
            }
            needNewSub = true
            var (dx, n1) = readTokNum(d, pos); pos = n1
            var (dy, n2) = readTokNum(d, pos); pos = n2
            cx += dx; cy += dy; startX = cx; startY = cy
            current.add(Point(cx, cy))
            while (!atPathEnd(d, pos)) {
                (dx, n1) = readTokNum(d, pos); pos = n1
                (dy, n2) = readTokNum(d, pos); pos = n2
                cx += dx; cy += dy; current.add(Point(cx, cy))
            }
        } else if (cmdVal == 76) { // L
            while (!atPathEnd(d, pos)) {
                var (x, n1) = readTokNum(d, pos); pos = n1
                var (y, n2) = readTokNum(d, pos); pos = n2
                cx = x; cy = y; current.add(Point(x, y))
            }
        } else if (cmdVal == 108) { // l
            while (!atPathEnd(d, pos)) {
                var (dx, n1) = readTokNum(d, pos); pos = n1
                var (dy, n2) = readTokNum(d, pos); pos = n2
                cx += dx; cy += dy; current.add(Point(cx, cy))
            }
        } else if (cmdVal == 72) { // H
            while (!atPathEnd(d, pos)) {
                var (x, n1) = readTokNum(d, pos); pos = n1
                cx = x; current.add(Point(cx, cy))
            }
        } else if (cmdVal == 104) { // h
            while (!atPathEnd(d, pos)) {
                var (dx, n1) = readTokNum(d, pos); pos = n1
                cx += dx; current.add(Point(cx, cy))
            }
        } else if (cmdVal == 86) { // V
            while (!atPathEnd(d, pos)) {
                var (y, n1) = readTokNum(d, pos); pos = n1
                cy = y; current.add(Point(cx, cy))
            }
        } else if (cmdVal == 118) { // v
            while (!atPathEnd(d, pos)) {
                var (dy, n1) = readTokNum(d, pos); pos = n1
                cy += dy; current.add(Point(cx, cy))
            }
        } else if (cmdVal == 67) { // C
            while (!atPathEnd(d, pos)) {
                var (x1, n1) = readTokNum(d, pos); pos = n1
                var (y1, n2) = readTokNum(d, pos); pos = n2
                var (x2, n3) = readTokNum(d, pos); pos = n3
                var (y2, n4) = readTokNum(d, pos); pos = n4
                var (x, n5) = readTokNum(d, pos); pos = n5
                var (y, n6) = readTokNum(d, pos); pos = n6
                var step: Int64 = 1
                while (step <= steps) {
                    let t = Float64(step) / Float64(steps)
                    current.add(Point(cubicBez(cx, x1, x2, x, t), cubicBez(cy, y1, y2, y, t)))
                    step++
                }
                lastCX2 = x2; lastCY2 = y2; lastCX = x1; lastCY = y1
                cx = x; cy = y
            }
        } else if (cmdVal == 99) { // c
            while (!atPathEnd(d, pos)) {
                var (x1, n1) = readTokNum(d, pos); pos = n1
                var (y1, n2) = readTokNum(d, pos); pos = n2
                var (x2, n3) = readTokNum(d, pos); pos = n3
                var (y2, n4) = readTokNum(d, pos); pos = n4
                var (x, n5) = readTokNum(d, pos); pos = n5
                var (y, n6) = readTokNum(d, pos); pos = n6
                var ax1 = cx + x1; var ay1 = cy + y1
                var ax2 = cx + x2; var ay2 = cy + y2
                var ax = cx + x; var ay = cy + y
                var step: Int64 = 1
                while (step <= steps) {
                    let t = Float64(step) / Float64(steps)
                    current.add(Point(cubicBez(cx, ax1, ax2, ax, t), cubicBez(cy, ay1, ay2, ay, t)))
                    step++
                }
                lastCX2 = ax2; lastCY2 = ay2; lastCX = ax1; lastCY = ay1
                cx = ax; cy = ay
            }
        } else if (cmdVal == 83) { // S
            while (!atPathEnd(d, pos)) {
                var (x2, n1) = readTokNum(d, pos); pos = n1
                var (y2, n2) = readTokNum(d, pos); pos = n2
                var (x, n3) = readTokNum(d, pos); pos = n3
                var (y, n4) = readTokNum(d, pos); pos = n4
                var x1 = cx; var y1 = cy
                if (lastCmd == 67 || lastCmd == 83 || lastCmd == 99 || lastCmd == 115) {
                    x1 = 2.0 * cx - lastCX2; y1 = 2.0 * cy - lastCY2
                }
                var step: Int64 = 1
                while (step <= steps) {
                    let t = Float64(step) / Float64(steps)
                    current.add(Point(cubicBez(cx, x1, x2, x, t), cubicBez(cy, y1, y2, y, t)))
                    step++
                }
                lastCX2 = x2; lastCY2 = y2; lastCX = x1; lastCY = y1
                cx = x; cy = y
            }
        } else if (cmdVal == 115) { // s
            while (!atPathEnd(d, pos)) {
                var (x2, n1) = readTokNum(d, pos); pos = n1
                var (y2, n2) = readTokNum(d, pos); pos = n2
                var (x, n3) = readTokNum(d, pos); pos = n3
                var (y, n4) = readTokNum(d, pos); pos = n4
                var ax2 = cx + x2; var ay2 = cy + y2
                var ax = cx + x; var ay = cy + y
                var x1 = cx; var y1 = cy
                if (lastCmd == 67 || lastCmd == 83 || lastCmd == 99 || lastCmd == 115) {
                    x1 = 2.0 * cx - lastCX2; y1 = 2.0 * cy - lastCY2
                }
                var step: Int64 = 1
                while (step <= steps) {
                    let t = Float64(step) / Float64(steps)
                    current.add(Point(cubicBez(cx, x1, ax2, ax, t), cubicBez(cy, y1, ay2, ay, t)))
                    step++
                }
                lastCX2 = ax2; lastCY2 = ay2; lastCX = x1; lastCY = y1
                cx = ax; cy = ay
            }
        } else if (cmdVal == 81) { // Q
            while (!atPathEnd(d, pos)) {
                var (x1, n1) = readTokNum(d, pos); pos = n1
                var (y1, n2) = readTokNum(d, pos); pos = n2
                var (x, n3) = readTokNum(d, pos); pos = n3
                var (y, n4) = readTokNum(d, pos); pos = n4
                var step: Int64 = 1
                while (step <= steps) {
                    let t = Float64(step) / Float64(steps)
                    current.add(Point(quadBez(cx, x1, x, t), quadBez(cy, y1, y, t)))
                    step++
                }
                lastCX = x1; lastCY = y1; cx = x; cy = y
            }
        } else if (cmdVal == 113) { // q
            while (!atPathEnd(d, pos)) {
                var (x1, n1) = readTokNum(d, pos); pos = n1
                var (y1, n2) = readTokNum(d, pos); pos = n2
                var (x, n3) = readTokNum(d, pos); pos = n3
                var (y, n4) = readTokNum(d, pos); pos = n4
                var ax1 = cx + x1; var ay1 = cy + y1
                var ax = cx + x; var ay = cy + y
                var step: Int64 = 1
                while (step <= steps) {
                    let t = Float64(step) / Float64(steps)
                    current.add(Point(quadBez(cx, ax1, ax, t), quadBez(cy, ay1, ay, t)))
                    step++
                }
                lastCX = ax1; lastCY = ay1; cx = ax; cy = ay
            }
        } else if (cmdVal == 84) { // T
            while (!atPathEnd(d, pos)) {
                var (x, n1) = readTokNum(d, pos); pos = n1
                var (y, n2) = readTokNum(d, pos); pos = n2
                var x1 = cx; var y1 = cy
                if (lastCmd == 81 || lastCmd == 84 || lastCmd == 113 || lastCmd == 116) {
                    x1 = 2.0 * cx - lastCX; y1 = 2.0 * cy - lastCY
                }
                var step: Int64 = 1
                while (step <= steps) {
                    let t = Float64(step) / Float64(steps)
                    current.add(Point(quadBez(cx, x1, x, t), quadBez(cy, y1, y, t)))
                    step++
                }
                lastCX = x1; lastCY = y1; cx = x; cy = y
            }
        } else if (cmdVal == 116) { // t
            while (!atPathEnd(d, pos)) {
                var (x, n1) = readTokNum(d, pos); pos = n1
                var (y, n2) = readTokNum(d, pos); pos = n2
                var ax = cx + x; var ay = cy + y
                var x1 = cx; var y1 = cy
                if (lastCmd == 81 || lastCmd == 84 || lastCmd == 113 || lastCmd == 116) {
                    x1 = 2.0 * cx - lastCX; y1 = 2.0 * cy - lastCY
                }
                var step: Int64 = 1
                while (step <= steps) {
                    let t = Float64(step) / Float64(steps)
                    current.add(Point(quadBez(cx, x1, ax, t), quadBez(cy, y1, ay, t)))
                    step++
                }
                lastCX = x1; lastCY = y1; cx = ax; cy = ay
            }
        } else if (cmdVal == 65) { // A (absolute arc)
            while (!atPathEnd(d, pos)) {
                var (_rx, n1) = readTokNum(d, pos); pos = n1
                var (_ry, n2) = readTokNum(d, pos); pos = n2
                var (_xRot, n3) = readTokNum(d, pos); pos = n3
                var (_fArc, n4) = readTokNum(d, pos); pos = n4
                var (_fSweep, n5) = readTokNum(d, pos); pos = n5
                var (ex, n6) = readTokNum(d, pos); pos = n6
                var (ey, n7) = readTokNum(d, pos); pos = n7
                // Approximate arc with line segments using simple subdivision
                let arcSegs = 64
                var step: Int64 = 1
                while (step <= arcSegs) {
                    let t = Float64(step) / Float64(arcSegs)
                    // Simple linear interpolation as approximation
                    let px = cx + (ex - cx) * t
                    let py = cy + (ey - cy) * t
                    current.add(Point(px, py))
                    step++
                }
                cx = ex; cy = ey
            }
        } else if (cmdVal == 97) { // a (relative arc)
            while (!atPathEnd(d, pos)) {
                var (_rx, n1) = readTokNum(d, pos); pos = n1
                var (_ry, n2) = readTokNum(d, pos); pos = n2
                var (_xRot, n3) = readTokNum(d, pos); pos = n3
                var (_fArc, n4) = readTokNum(d, pos); pos = n4
                var (_fSweep, n5) = readTokNum(d, pos); pos = n5
                var (dx, n6) = readTokNum(d, pos); pos = n6
                var (dy, n7) = readTokNum(d, pos); pos = n7
                let aex = cx + dx; let aey = cy + dy
                let arcSegs = 64
                var step: Int64 = 1
                while (step <= arcSegs) {
                    let t = Float64(step) / Float64(arcSegs)
                    let px = cx + (aex - cx) * t
                    let py = cy + (aey - cy) * t
                    current.add(Point(px, py))
                    step++
                }
                cx = aex; cy = aey
            }
        } else if (cmdVal == 90 || cmdVal == 122) { // Z z
            if (current.size > 0) {
                cx = startX; cy = startY
                current.add(Point(startX, startY))
                subpaths.add(current)
                current = ArrayList<Point>()
            }
        }
        lastCmd = cmdVal
    }
    if (current.size > 0) {
        subpaths.add(current)
    }
    return subpaths
}

class SVGElement {
    var isPath: Bool = false
    var fill: (Byte, Byte, Byte) = (UInt8(0), UInt8(0), UInt8(0))
    var polygons: ArrayList<ArrayList<Point>> = ArrayList<ArrayList<Point>>()
    var pathD: String = ""
    var transform: Transform = Transform()
    var children: ArrayList<SVGElement> = ArrayList<SVGElement>()
    var isGroup: Bool = false
    var fillRule: String = "evenodd"

    func getSubPaths(): ArrayList<ArrayList<Point>> {
        if (isPath) { return flattenPath(pathD) }
        return polygons
    }

    func collectElements(result: ArrayList<(ArrayList<ArrayList<Point>>, (Byte, Byte, Byte), Transform)>): Unit {
        for (child in children) {
            if (child.isGroup) {
                child.collectElements(result)
            } else {
                let subs = child.getSubPaths()
                var hasPts = false
                for (sp in subs) {
                    if (sp.size >= 2) { hasPts = true; break }
                }
                if (hasPts) {
                    result.add((subs, child.fill, child.transform))
                }
            }
        }
    }
}

func extractAttr(tag: String, name: String): String {
    var p = name + "=\""
    let idx = strIdx1(tag, p)
    if (idx >= 0) {
        let start = idx + p.size
        let end = strIdx(tag, "\"", start)
        if (end > start) { return tag[start..end] }
    }
    return ""
}

func splitArgs(args: String): ArrayList<String> {
    let result = ArrayList<String>()
    var current = ""
    var i: Int64 = 0
    while (i < args.size) {
        let c = args[i]
        if (c == UInt8(44) || c == UInt8(32) || c == UInt8(9)) {
            if (!current.isEmpty()) { result.add(current); current = "" }
        } else {
            current = current + String(Array<Rune>(1, {_ => Rune(c)}))
        }
        i++
    }
    if (!current.isEmpty()) { result.add(current) }
    return result
}

func parseTransform(s: String): Transform {
    if (s.isEmpty()) { return Transform() }
    var tx = 0.0; var ty = 0.0; var sx = 1.0; var sy = 1.0
    var rest = s
    let ti = strIdx1(rest, "translate")
    if (ti >= 0) {
        rest = rest[ti + 9..]
        let ps = strIdx1(rest, "(")
        let pe = strIdx1(rest, ")")
        if (ps >= 0 && pe > ps) {
            let parts = splitArgs(rest[ps + 1..pe])
            if (parts.size >= 1) { tx = Float64.parse(parts[0]) }
            if (parts.size >= 2) { ty = Float64.parse(parts[1]) }
            else { ty = tx }
            rest = rest[pe + 1..]
        }
    }
    let si = strIdx1(rest, "scale")
    if (si >= 0) {
        rest = rest[si + 5..]
        let ps = strIdx1(rest, "(")
        let pe = strIdx1(rest, ")")
        if (ps >= 0 && pe > ps) {
            let parts = splitArgs(rest[ps + 1..pe])
            if (parts.size >= 1) { sx = Float64.parse(parts[0]) }
            if (parts.size >= 2) { sy = Float64.parse(parts[1]) }
            else { sy = sx }
        }
    }
    return Transform(tx, ty, sx, sy)
}

func parsePolygonPoints(s: String): ArrayList<Point> {
    let pts = ArrayList<Point>()
    var current = ""
    var values = ArrayList<Float64>()
    var i: Int64 = 0
    while (i < s.size) {
        let c = s[i]
        if (c == UInt8(44) || c == UInt8(32) || c == UInt8(9) || c == UInt8(10) || c == UInt8(13)) {
            if (!current.isEmpty()) { values.add(Float64.parse(current)); current = "" }
        } else {
            current = current + String(Array<Rune>(1, {_ => Rune(c)}))
        }
        i++
    }
    if (!current.isEmpty()) { values.add(Float64.parse(current)) }
    var vi: Int64 = 0
    while (vi + 1 < values.size) {
        pts.add(Point(values[vi], values[vi + 1]))
        vi += 2
    }
    return pts
}

func extractStyleFill(tag: String): String {
    let style = extractAttr(tag, "style")
    if (style.isEmpty()) { return "" }
    let idx = strIdx1(style, "fill:")
    if (idx < 0) { return "" }
    let start = idx + 5
    var end = strIdx1(style, ";")
    if (end < 0 || end <= start) { end = style.size }
    return style[start..end]
}

func getTagName(tag: String): String {
    var i: Int64 = 1
    while (i < tag.size) {
        let c = tag[i]
        if (c == UInt8(32) || c == UInt8(9) || c == UInt8(10) || c == UInt8(13) ||
            c == UInt8(62) || c == UInt8(47)) {
            return tag[1..i]
        }
        i++
    }
    return tag[1..]
}

func findClosingTag(content: String, startPos: Int64, tagName: String): Int64 {
    var depth: Int64 = 1
    var pos = startPos
    var openTag = "<" + tagName
    var closeTag = "</" + tagName + ">"
    while (pos < content.size && depth > 0) {
        let nc = strIdx(content, closeTag, pos)
        if (nc < 0) { return -1 }
        let no = strIdx(content, openTag, pos)
        if (no >= 0 && no < nc) {
            depth++; pos = no + 1
        } else {
            depth--
            if (depth == 0) { return nc }
            pos = nc + 1
        }
    }
    return -1
}

func resolveFill(tag: String, parentFill: (Byte, Byte, Byte)): (Byte, Byte, Byte) {
    let sf = extractStyleFill(tag)
    if (!sf.isEmpty()) { return parseColor(sf) }
    let fa = extractAttr(tag, "fill")
    if (!fa.isEmpty()) { return parseColor(fa) }
    return parentFill
}

func extractAttrFloat(tag: String, name: String, def: Float64): Float64 {
    let s = extractAttr(tag, name)
    if (!s.isEmpty()) {
        try { return Float64.parse(s) } catch (_: Exception) {}
    }
    return def
}

func extractAttrFloat2(tag: String, name: String): Float64 {
    return extractAttrFloat(tag, name, 0.0)
}

func resolveFillRule(tag: String, parentRule: String): String {
    let fr = extractAttr(tag, "fill-rule")
    if (!fr.isEmpty()) { return fr }
    let style = extractAttr(tag, "style")
    if (!style.isEmpty()) {
        let idx = strIdx1(style, "fill-rule:")
        if (idx >= 0) {
            let start = idx + 10
            var end = strIdx1(style, ";")
            if (end < 0 || end <= start) { end = style.size }
            let val = style[start..end]
            if (val == "nonzero" || val == "evenodd") { return val }
        }
    }
    return parentRule
}

func parseElems(content: String, startPos: Int64, parent: ArrayList<SVGElement>,
                parentFill: (Byte, Byte, Byte), parentTransform: Transform,
                parentFillRule: String): Unit {
    var pos = startPos
    while (pos < content.size) {
        let tagStart = strIdx(content, "<", pos)
        if (tagStart < 0 || tagStart + 1 >= content.size) { break }
        if (content[tagStart + 1] == UInt8(47)) {
            let te = strIdx(content, ">", tagStart)
            if (te < 0) { break }
            pos = te + 1; continue
        }
        let nc = content[tagStart + 1]
        if (nc == UInt8(63) || nc == UInt8(33) || nc == UInt8(37)) {
            let te = strIdx(content, ">", tagStart)
            if (te < 0) { break }
            pos = te + 1; continue
        }
        let tagEnd = strIdx(content, ">", tagStart)
        if (tagEnd < 0) { break }
        var posAfter = tagEnd + 1
        var te2 = tagEnd
        if (tagEnd > tagStart && content[tagEnd - 1] == UInt8(47)) { te2 = tagEnd - 1 }
        let tagContent = content[tagStart..te2]
        let tagName = getTagName(tagContent)

        if (tagName == "g") {
            var gFill = parentFill
            let fa = extractAttr(tagContent, "fill")
            if (!fa.isEmpty()) { gFill = parseColor(fa) }
            let sf = extractStyleFill(tagContent)
            if (!sf.isEmpty()) { gFill = parseColor(sf) }
            var gTransform = parentTransform
            let ta = extractAttr(tagContent, "transform")
            if (!ta.isEmpty()) {
                let lt = parseTransform(ta)
                gTransform = Transform(
                    parentTransform.tx * lt.sx + lt.tx,
                    parentTransform.ty * lt.sy + lt.ty,
                    parentTransform.sx * lt.sx,
                    parentTransform.sy * lt.sy
                )
            }
            let gFillRule = resolveFillRule(tagContent, parentFillRule)
            let closeG = findClosingTag(content, posAfter, "g")
            if (closeG >= 0) {
                let group = SVGElement()
                group.isGroup = true
                group.fill = gFill
                group.transform = gTransform
                group.fillRule = gFillRule
                parseElems(content, posAfter, group.children, gFill, gTransform, gFillRule)
                parent.add(group)
                pos = closeG + 4
            } else {
                pos = posAfter
            }
        } else if (tagName == "polygon") {
            let elem = SVGElement()
            elem.transform = parentTransform
            elem.fillRule = resolveFillRule(tagContent, parentFillRule)
            let pa = extractAttr(tagContent, "points")
            if (!pa.isEmpty()) {
                let pts = parsePolygonPoints(pa)
                if (pts.size >= 2) {
                    let arr = ArrayList<ArrayList<Point>>()
                    arr.add(pts)
                    elem.polygons = arr
                }
            }
            elem.fill = resolveFill(tagContent, parentFill)
            parent.add(elem)
            pos = posAfter
        } else if (tagName == "polyline") {
            let elem = SVGElement()
            elem.isPath = true
            elem.transform = parentTransform
            elem.fillRule = resolveFillRule(tagContent, parentFillRule)
            let pa = extractAttr(tagContent, "points")
            if (!pa.isEmpty()) {
                let pts = parsePolygonPoints(pa)
                if (pts.size >= 2) {
                    // polyline is same as path with M...L... (no close)
                    var d = "M${pts[0].x} ${pts[0].y}"
                    var pi: Int64 = 1
                    while (pi < pts.size) {
                        d = d + " L${pts[pi].x} ${pts[pi].y}"
                        pi++
                    }
                    elem.pathD = d
                }
            }
            elem.fill = resolveFill(tagContent, parentFill)
            parent.add(elem)
            pos = posAfter
        } else if (tagName == "rect") {
            let elem = SVGElement()
            elem.isPath = true
            elem.transform = parentTransform
            elem.fillRule = resolveFillRule(tagContent, parentFillRule)
            let rx = extractAttrFloat2(tagContent, "x")
            let ry = extractAttrFloat2(tagContent, "y")
            let rw = extractAttrFloat2(tagContent, "width")
            let rh = extractAttrFloat2(tagContent, "height")
            if (rw > 0.0 && rh > 0.0) { elem.pathD = rectToPathD(rx, ry, rw, rh) }
            elem.fill = resolveFill(tagContent, parentFill)
            parent.add(elem)
            pos = posAfter
        } else if (tagName == "circle") {
            let elem = SVGElement()
            elem.isPath = true
            elem.transform = parentTransform
            elem.fillRule = resolveFillRule(tagContent, parentFillRule)
            let ccx = extractAttrFloat2(tagContent, "cx")
            let ccy = extractAttrFloat2(tagContent, "cy")
            let cr = extractAttrFloat2(tagContent, "r")
            if (cr > 0.0) { elem.pathD = circleToPathD(ccx, ccy, cr) }
            elem.fill = resolveFill(tagContent, parentFill)
            parent.add(elem)
            pos = posAfter
        } else if (tagName == "ellipse") {
            let elem = SVGElement()
            elem.isPath = true
            elem.transform = parentTransform
            elem.fillRule = resolveFillRule(tagContent, parentFillRule)
            let ecx = extractAttrFloat2(tagContent, "cx")
            let ecy = extractAttrFloat2(tagContent, "cy")
            let erx = extractAttrFloat2(tagContent, "rx")
            let ery = extractAttrFloat2(tagContent, "ry")
            if (erx > 0.0 && ery > 0.0) { elem.pathD = ellipseToPathD(ecx, ecy, erx, ery) }
            elem.fill = resolveFill(tagContent, parentFill)
            parent.add(elem)
            pos = posAfter
        } else if (tagName == "line") {
            let elem = SVGElement()
            elem.isPath = true
            elem.transform = parentTransform
            elem.fillRule = resolveFillRule(tagContent, parentFillRule)
            let lx1 = extractAttrFloat2(tagContent, "x1")
            let ly1 = extractAttrFloat2(tagContent, "y1")
            let lx2 = extractAttrFloat2(tagContent, "x2")
            let ly2 = extractAttrFloat2(tagContent, "y2")
            elem.pathD = "M${lx1} ${ly1} L${lx2} ${ly2}"
            elem.fill = resolveFill(tagContent, parentFill)
            parent.add(elem)
            pos = posAfter
        } else if (tagName == "path") {
            let elem = SVGElement()
            elem.isPath = true
            elem.transform = parentTransform
            elem.fillRule = resolveFillRule(tagContent, parentFillRule)
            let da = extractAttr(tagContent, "d")
            if (!da.isEmpty()) { elem.pathD = da }
            elem.fill = resolveFill(tagContent, parentFill)
            parent.add(elem)
            pos = posAfter
        } else {
            pos = posAfter
        }
    }
}

func parseSVG(svgContent: String): (Float64, Float64, Float64, Float64, ArrayList<SVGElement>) {
    var vbX = 0.0; var vbY = 0.0; var vbW = 1000.0; var vbH = 1000.0
    let elements = ArrayList<SVGElement>()
    if (strIdx1(svgContent, "<svg") < 0) {
        return (vbX, vbY, vbW, vbH, elements)
    }
    // Extract svg tag for attribute parsing
    let svgStart = strIdx1(svgContent, "<svg")
    let svgEnd = strIdx(svgContent, ">", svgStart)
    var svgTag = ""
    if (svgStart >= 0 && svgEnd > svgStart) { svgTag = svgContent[svgStart..svgEnd] }
    let vb = extractAttr(svgTag, "viewBox")
    if (!vb.isEmpty()) {
        let parts = splitArgs(vb)
        if (parts.size >= 4) {
            vbX = Float64.parse(parts[0]); vbY = Float64.parse(parts[1])
            vbW = Float64.parse(parts[2]); vbH = Float64.parse(parts[3])
        }
    } else {
        // Fallback to width/height attributes
        let sw = extractAttr(svgTag, "width")
        let sh = extractAttr(svgTag, "height")
        if (!sw.isEmpty() && !sh.isEmpty()) {
            // Strip "px" suffix if present
            var wStr = sw; var hStr = sh
            if (wStr.size > 2 && wStr[wStr.size - 1] == UInt8(120) && wStr[wStr.size - 2] == UInt8(112)) {
                wStr = wStr[0..wStr.size - 2]
            }
            if (hStr.size > 2 && hStr[hStr.size - 1] == UInt8(120) && hStr[hStr.size - 2] == UInt8(112)) {
                hStr = hStr[0..hStr.size - 2]
            }
            try {
                vbW = Float64.parse(wStr)
                vbH = Float64.parse(hStr)
            } catch (_: Exception) {}
        }
    }
    parseElems(svgContent, 0, elements, (UInt8(0), UInt8(0), UInt8(0)), Transform(), "evenodd")
    return (vbX, vbY, vbW, vbH, elements)
}

func renderToBMP(doc: (Float64, Float64, Float64, Float64, ArrayList<SVGElement>),
                 width: Int64, height: Int64): Array<Byte> {
    let (vbX, vbY, vbW, vbH, rootElements) = doc
    // Accumulator for supersampled coverage: Float64 per pixel per channel
    var accumR = Array<Float64>(width * height, {_ => 0.0})
    var accumG = Array<Float64>(width * height, {_ => 0.0})
    var accumB = Array<Float64>(width * height, {_ => 0.0})
    var coverage = Array<Float64>(width * height, {_ => 0.0})
    let scaleX = Float64(width) / vbW
    let scaleY = Float64(height) / vbH
    let samples = 16
    let invSamples = 1.0 / Float64(samples)
    let drawables = ArrayList<(ArrayList<ArrayList<Point>>, (Byte, Byte, Byte), Transform)>()
    for (elem in rootElements) {
        if (elem.isGroup) {
            elem.collectElements(drawables)
        } else {
            let subs = elem.getSubPaths()
            var hasPts = false
            for (sp in subs) {
                if (sp.size >= 2) { hasPts = true; break }
            }
            if (hasPts) {
                drawables.add((subs, elem.fill, elem.transform))
            }
        }
    }
    // Supersample: 4x4 grid per pixel for higher quality
    // Sample offsets at 0.125, 0.375, 0.625, 0.875 (16 samples total)
    let offArr = Array<Float64>(4, {i => Float64(i) * 0.25 + 0.125})
    var sy: Int64 = 0
    while (sy < 4) {
        let offY = offArr[sy]
        var sx: Int64 = 0
        while (sx < 4) {
            let offX = offArr[sx]
            var di: Int64 = 0
            while (di < drawables.size) {
                let (subpaths, color, transform) = drawables[di]
                let (r, g, b) = color
                // Transform ALL subpaths first, collect edges for unified even-odd
                let allEdges = ArrayList<(Float64, Float64, Float64, Float64)>() // (x0, y0, x1, y1)
                var globalMinY = Float64(height); var globalMaxY = 0.0
                var si: Int64 = 0
                while (si < subpaths.size) {
                    let origPts = subpaths[si]
                    let tPts = ArrayList<Point>()
                    for (pt in origPts) {
                        let tp = transform.apply(pt)
                        tPts.add(Point((tp.x - vbX) * scaleX, (tp.y - vbY) * scaleY))
                    }
                    let n = tPts.size
                    if (n >= 2) {
                        var ei: Int64 = 0
                        while (ei < n) {
                            let ej = (ei + 1) % n
                            let y0 = tPts[ei].y; let y1 = tPts[ej].y
                            let x0 = tPts[ei].x; let x1 = tPts[ej].x
                            if (y0 < globalMinY) { globalMinY = y0 }
                            if (y0 > globalMaxY) { globalMaxY = y0 }
                            allEdges.add((x0, y0, x1, y1))
                            ei++
                        }
                    }
                    si++
                }
                if (allEdges.size == 0) { di++; continue }
                var scanStart = max(0, Int64(globalMinY))
                var scanEnd = min(height - 1, Int64(globalMaxY))
                var scanY = scanStart
                while (scanY <= scanEnd) {
                    let y = Float64(scanY) + offY
                    var ints = ArrayList<Float64>()
                    // Collect intersections from ALL edges of ALL subpaths
                    var ei: Int64 = 0
                    while (ei < allEdges.size) {
                        let (x0, y0, x1, y1) = allEdges[ei]
                        if ((y0 < y && y1 >= y) || (y1 < y && y0 >= y)) {
                            let dy = y1 - y0
                            if (abs(dy) > 1e-10) {
                                ints.add(x0 + (y - y0) / dy * (x1 - x0))
                            }
                        }
                        ei++
                    }
                    sort(ints)
                    // Even-odd fill: fill between pairs of sorted intersections
                    var k: Int64 = 0
                    while (k + 1 < ints.size) {
                        var xS = ints[k]
                        var xE = ints[k + 1]
                        let colStart = Int64(ceil(xS - offX))
                        let colEnd = Int64(ceil(xE - offX)) - 1
                        var cx = colStart
                        while (cx <= colEnd) {
                            if (cx >= 0 && cx < width) {
                                let bmpY = height - 1 - scanY
                                let pidx = bmpY * width + cx
                                if (pidx >= 0 && pidx < width * height) {
                                    accumR[pidx] += Float64(Int64(r)) * invSamples
                                    accumG[pidx] += Float64(Int64(g)) * invSamples
                                    accumB[pidx] += Float64(Int64(b)) * invSamples
                                    coverage[pidx] += invSamples
                                }
                            }
                            cx++
                        }
                        k += 2
                    }
                    scanY++
                }
                di++
            }
            sx++
        }
        sy++
    }
    // Blend: alpha = coverage, background = white (255)
    let pixels = Array<Byte>(width * height * 3, {_ => UInt8(255)})
    var pidx: Int64 = 0
    while (pidx < width * height) {
        let a = coverage[pidx]
        if (a > 0.001) {
            let ir = Int64(accumR[pidx] / a + 0.5)
            let ig = Int64(accumG[pidx] / a + 0.5)
            let ib = Int64(accumB[pidx] / a + 0.5)
            var br = UInt8(255); var bg = UInt8(255); var bb = UInt8(255)
            if (a >= 0.999) {
                br = UInt8(ir); bg = UInt8(ig); bb = UInt8(ib)
            } else {
                br = UInt8(Int64(Float64(255.0) * (1.0 - a) + Float64(ir) * a + 0.5))
                bg = UInt8(Int64(Float64(255.0) * (1.0 - a) + Float64(ig) * a + 0.5))
                bb = UInt8(Int64(Float64(255.0) * (1.0 - a) + Float64(ib) * a + 0.5))
            }
            pixels[pidx * 3] = bb; pixels[pidx * 3 + 1] = bg; pixels[pidx * 3 + 2] = br
        }
        pidx++
    }
    return pixels
}

func writeBMP(filename: String, width: Int64, height: Int64, pixels: Array<Byte>): Unit {
    var rowSize = ((width * 3 + 3) / 4) * 4
    let padding = rowSize - width * 3
    let imageSize = rowSize * height
    let fileSize = 54 + imageSize
    // Workaround: write BMP data to memory buffer, then write all at once
    var bufSize = 54 + imageSize
    var buf = ArrayList<Byte>()
    var bi: Int64 = 0
    while (bi < bufSize) { buf.add(UInt8(0)); bi++ }
    // Write BMP header into buffer
    buf[0] = UInt8(0x42); buf[1] = UInt8(0x4D)
    buf[2] = UInt8(fileSize & 0xFF); buf[3] = UInt8((fileSize >> 8) & 0xFF)
    buf[4] = UInt8((fileSize >> 16) & 0xFF); buf[5] = UInt8((fileSize >> 24) & 0xFF)
    buf[6] = UInt8(0); buf[7] = UInt8(0); buf[8] = UInt8(0); buf[9] = UInt8(0)
    buf[10] = UInt8(54); buf[11] = UInt8(0); buf[12] = UInt8(0); buf[13] = UInt8(0)
    buf[14] = UInt8(40); buf[15] = UInt8(0); buf[16] = UInt8(0); buf[17] = UInt8(0)
    buf[18] = UInt8(width & 0xFF); buf[19] = UInt8((width >> 8) & 0xFF)
    buf[20] = UInt8((width >> 16) & 0xFF); buf[21] = UInt8((width >> 24) & 0xFF)
    buf[22] = UInt8(height & 0xFF); buf[23] = UInt8((height >> 8) & 0xFF)
    buf[24] = UInt8((height >> 16) & 0xFF); buf[25] = UInt8((height >> 24) & 0xFF)
    buf[26] = UInt8(1); buf[27] = UInt8(0); buf[28] = UInt8(24); buf[29] = UInt8(0)
    buf[30] = UInt8(0); buf[31] = UInt8(0); buf[32] = UInt8(0); buf[33] = UInt8(0)
    buf[34] = UInt8(imageSize & 0xFF); buf[35] = UInt8((imageSize >> 8) & 0xFF)
    buf[36] = UInt8((imageSize >> 16) & 0xFF); buf[37] = UInt8((imageSize >> 24) & 0xFF)
    buf[38] = UInt8(19); buf[39] = UInt8(11); buf[40] = UInt8(0); buf[41] = UInt8(0)
    buf[42] = UInt8(19); buf[43] = UInt8(11); buf[44] = UInt8(0); buf[45] = UInt8(0)
    buf[46] = UInt8(0); buf[47] = UInt8(0); buf[48] = UInt8(0); buf[49] = UInt8(0)
    buf[50] = UInt8(0); buf[51] = UInt8(0); buf[52] = UInt8(0); buf[53] = UInt8(0)
    // Write pixel data into buffer
    var py2: Int64 = 0
    var boff: Int64 = 54
    while (py2 < height) {
        var px2: Int64 = 0
        while (px2 < width) {
            let idx = (py2 * width + px2) * 3
            buf[boff] = pixels[idx]; boff++
            buf[boff] = pixels[idx + 1]; boff++
            buf[boff] = pixels[idx + 2]; boff++
            px2++
        }
        var p2: Int64 = 0
        while (p2 < padding) { buf[boff] = UInt8(0); boff++; p2++     }
    py2++
}
// Write buffer to file
let os = File(filename, OpenMode.Write)
    os.write(buf.toArray())
    os.flush(); os.close()
}

func getDir(path: String): String {
    var lastSlash: Int64 = -1
    var i: Int64 = 0
    while (i < path.size) {
        if (path[i] == UInt8(47) || path[i] == UInt8(92)) { lastSlash = i }
        i++
    }
    if (lastSlash > 0) { return path[0..lastSlash + 1] }
    return ""
}

func getBaseName(path: String): String {
    var lastSlash: Int64 = -1
    var i: Int64 = 0
    while (i < path.size) {
        if (path[i] == UInt8(47) || path[i] == UInt8(92)) { lastSlash = i }
        i++
    }
    if (lastSlash >= 0) { return path[lastSlash + 1..] }
    return path
}

func replaceExt(path: String, newExt: String): String {
    let name = getBaseName(path)
    var lastDot: Int64 = -1
    var i: Int64 = name.size - 1
    while (i >= 0) {
        if (name[i] == UInt8(46)) { lastDot = i; break }
        if (name[i] == UInt8(47) || name[i] == UInt8(92)) { break }
        i--
    }
    if (lastDot > 0) { return getDir(path) + name[0..lastDot] + newExt }
    return path + newExt
}

main(args: Array<String>) {
    if (args.size < 1) {
        println("Usage: svg_renderer <input.svg> [output.bmp] [width] [height]")
        return
    }
    let inputPath = args[0]
    var outputPath = ""
    if (args.size >= 2) {
        outputPath = args[1]
    } else {
        // Default: same directory as input SVG, same basename but .bmp extension
        outputPath = replaceExt(inputPath, ".bmp")
    }
    var outWidth: Int64 = 800; var outHeight: Int64 = 800
    if (args.size >= 4) {
        outWidth = Int64.parse(args[2])
        outHeight = Int64.parse(args[3])
    }
    println("Reading ${inputPath}...")
    let content = readAllText(inputPath)
    println("Parsing SVG...")
    let doc = parseSVG(content)
    let (vbX, vbY, vbW, vbH, _) = doc
    let aspect = vbW / vbH
    var finalW = Float64(outWidth)
    var finalH = Float64(outHeight)
    if (finalW < finalH) {
        if (finalW < 1000.0) { finalW = 1000.0; finalH = finalW / aspect }
    } else {
        if (finalH < 1000.0) { finalH = 1000.0; finalW = finalH * aspect }
    }
    outWidth = Int64(finalW + 0.5)
    outHeight = Int64(finalH + 0.5)
    println("ViewBox: ${vbX} ${vbY} ${vbW} ${vbH}")
    println("Rendering to ${outWidth}x${outHeight}...")
    let pixels = renderToBMP(doc, outWidth, outHeight)
    println("Writing BMP to ${outputPath}...")
    writeBMP(outputPath, outWidth, outHeight, pixels)
    println("Done!")
}
