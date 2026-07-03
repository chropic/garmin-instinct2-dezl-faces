import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Boxed-panel TUI watchface for the Instinct 2 dezl Edition.
// 176x176 1-bit MIP display, circular subscreen in the top-right.
//
// Layout (white on black):
//   [SYS]   panel, top-left beside the subscreen: BAT / STP meters
//   (HR)    inside the physical subscreen circle, dot-matrix digits
//   [DATE]  full-width panel:  FRI 2026-07-03
//   [TIME]  full-width hero panel, 5x7 dot-matrix digits
//   prompt  "user@dezl:~$" footer line
class TuiFaceView extends WatchUi.WatchFace {

    private const MARGIN = 6;
    private const PANEL_TOP = 18;
    private const GAP = 4;
    private const METER_SEGS = 10;

    // Fallback subscreen geometry for the Instinct 2 family (176x176).
    // Overwritten in onLayout by WatchUi.getSubscreen() where available,
    // so the real device geometry always wins.
    private var _subX as Number = 94;
    private var _subY as Number = 0;
    private var _subW as Number = 82;
    private var _subH as Number = 82;

    private const DAY_NAMES = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];

    // 5x7 dot-matrix glyphs, one 5-bit row per entry, MSB = left column.
    private const DIGIT_COLS = 5;
    private const DIGIT_ROWS = 7;
    private const DIGITS = [
        [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E], // 0
        [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E], // 1
        [0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F], // 2
        [0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E], // 3
        [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02], // 4
        [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E], // 5
        [0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E], // 6
        [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08], // 7
        [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E], // 8
        [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C]  // 9
    ];

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Dc) as Void {
        if (WatchUi has :getSubscreen) {
            var sub = WatchUi.getSubscreen();
            if (sub != null) {
                _subX = sub.x;
                _subY = sub.y;
                _subW = sub.width;
                _subH = sub.height;
            }
        }
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var width = dc.getWidth();
        var height = dc.getHeight();
        var fullW = width - 2 * MARGIN;
        var tinyH = dc.getFontHeight(Graphics.FONT_TINY);

        var subBottom = _subY + _subH;
        var sysW = _subX - GAP - MARGIN;
        var sysH = subBottom - PANEL_TOP;

        var dateY = subBottom + GAP;
        var dateH = tinyH + 6;

        var timeY = dateY + dateH + GAP;
        var timeH = height - 20 - timeY;

        drawSysPanel(dc, MARGIN, PANEL_TOP, sysW, sysH);
        drawSubscreenHr(dc);
        drawDatePanel(dc, MARGIN, dateY, fullW, dateH);
        drawTimePanel(dc, MARGIN, timeY, fullW, timeH);
        drawPrompt(dc, width / 2, timeY + timeH + 2);
    }

    // --- panels ---------------------------------------------------------

    private function drawTimePanel(dc as Dc, x as Number, y as Number, w as Number, h as Number) as Void {
        drawPanel(dc, x, y, w, h, "TIME");

        var clock = System.getClockTime();
        var is24 = System.getDeviceSettings().is24Hour;
        var hour = clock.hour;
        var meridiem as String? = null;
        if (!is24) {
            meridiem = hour >= 12 ? "PM" : "AM";
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }
        var timeStr = hour.format(is24 ? "%02d" : "%d") + ":" + clock.min.format("%02d");

        // Largest dot pitch whose glyphs fit the panel.
        var pitch = (h - 6) / DIGIT_ROWS;
        while (pitch > 2 && matrixWidth(timeStr, pitch) > w - 10) {
            pitch--;
        }
        var glyphH = DIGIT_ROWS * pitch - 1;
        drawMatrix(dc, x + (w - matrixWidth(timeStr, pitch)) / 2,
            y + (h - glyphH) / 2 + 1, timeStr, pitch);

        if (meridiem != null) {
            dc.drawText(x + w - 5, y + 3, Graphics.FONT_XTINY, meridiem,
                Graphics.TEXT_JUSTIFY_RIGHT);
        }
    }

    private function drawSubscreenHr(dc as Dc) as Void {
        var cx = _subX + _subW / 2;
        var cy = _subY + _subH / 2;
        var r = (_subW < _subH ? _subW : _subH) / 2;

        dc.drawCircle(cx, cy, r - 2);

        var hr = currentHeartRate();
        var hrStr = (hr == null) ? "--" : hr.format("%d");
        dc.drawText(cx, cy - r / 2 + 2, Graphics.FONT_XTINY, "HR",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var pitch = 4;
        if (matrixWidth(hrStr, pitch) > 2 * (r - 8)) {
            pitch = 3;
        }
        var glyphH = DIGIT_ROWS * pitch - 1;
        drawMatrix(dc, cx - matrixWidth(hrStr, pitch) / 2, cy + 6 - glyphH / 2, hrStr, pitch);
    }

    private function drawDatePanel(dc as Dc, x as Number, y as Number, w as Number, h as Number) as Void {
        drawPanel(dc, x, y, w, h, "DATE");

        var now = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var dow = DAY_NAMES[(now.day_of_week as Number) - 1];
        var dateStr = dow + " " + now.year.format("%04d") + "-"
            + now.month.format("%02d") + "-" + now.day.format("%02d");
        dc.drawText(x + w / 2, y + h / 2 + 1, Graphics.FONT_TINY, dateStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Compact stacked meters: label + value line, full-width bar below each.
    private function drawSysPanel(dc as Dc, x as Number, y as Number, w as Number, h as Number) as Void {
        drawPanel(dc, x, y, w, h, "SYS");

        var xtinyH = dc.getFontHeight(Graphics.FONT_XTINY);
        var rowX = x + 5;
        var rowW = w - 10;
        var barH = 7;

        var stats = System.getSystemStats();
        var battery = stats.battery;
        var batRatio = (battery == null) ? 0.0 : battery / 100.0;
        var batStr = (battery == null) ? "--" : battery.toNumber().format("%d") + "%";

        var info = ActivityMonitor.getInfo();
        var steps = info.steps;
        var goal = info.stepGoal;
        var stepRatio = 0.0;
        if (steps != null && goal != null && goal > 0) {
            stepRatio = steps.toFloat() / goal;
        }
        var stepStr = (steps == null) ? "--" : formatSteps(steps);

        var t1 = y + 9;
        var b1 = t1 + xtinyH + 1;
        var t2 = b1 + barH + 3;
        var b2 = t2 + xtinyH + 1;

        drawStackedMeter(dc, rowX, t1, b1, rowW, barH, "BAT", batRatio, batStr);
        drawStackedMeter(dc, rowX, t2, b2, rowW, barH, "STP", stepRatio, stepStr);
    }

    private function drawPrompt(dc as Dc, cx as Number, y as Number) as Void {
        if (y + dc.getFontHeight(Graphics.FONT_XTINY) <= dc.getHeight() - 2) {
            dc.drawText(cx, y, Graphics.FONT_XTINY, "user@dezl:~$",
                Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // --- TUI drawing helpers ----------------------------------------------

    // 1px frame with the label knocked into the top border, terminal style.
    private function drawPanel(dc as Dc, x as Number, y as Number, w as Number, h as Number, label as String) as Void {
        dc.drawRectangle(x, y, w, h);

        var font = Graphics.FONT_XTINY;
        var labelW = dc.getTextWidthInPixels(label, font);
        var labelH = dc.getFontHeight(font);
        var lx = x + 10;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(lx - 3, y - labelH / 2, labelW + 6, labelH);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(lx, y - labelH / 2, font, label, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // Label left, value right, segmented bar underneath.
    private function drawStackedMeter(dc as Dc, x as Number, textY as Number, barY as Number, w as Number, barH as Number, label as String, ratio as Float, value as String) as Void {
        var font = Graphics.FONT_XTINY;
        dc.drawText(x, textY, font, label, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(x + w, textY, font, value, Graphics.TEXT_JUSTIFY_RIGHT);
        drawMeter(dc, x, barY, w, barH, ratio);
    }

    private function drawMeter(dc as Dc, x as Number, y as Number, w as Number, h as Number, ratio as Float) as Void {
        if (ratio < 0) {
            ratio = 0.0;
        }
        if (ratio > 1) {
            ratio = 1.0;
        }
        dc.drawRectangle(x, y, w, h);

        var inner = w - 4;
        var segW = (inner - (METER_SEGS - 1)) / METER_SEGS;
        var filled = Math.round(ratio * METER_SEGS).toNumber();
        for (var i = 0; i < filled; i++) {
            dc.fillRectangle(x + 2 + i * (segW + 1), y + 2, segW, h - 4);
        }
    }

    // --- dot-matrix digits --------------------------------------------------

    // Width of a digit string ('0'-'9', ':', '-') at the given dot pitch.
    // A dot is (pitch - 1) px with a 1 px gap; chars are one pitch apart.
    private function matrixWidth(text as String, pitch as Number) as Number {
        var chars = text.toCharArray();
        var w = 0;
        for (var i = 0; i < chars.size(); i++) {
            w += (chars[i] == ':') ? (pitch - 1) : (DIGIT_COLS * pitch - 1);
            if (i < chars.size() - 1) {
                w += pitch;
            }
        }
        return w;
    }

    private function drawMatrix(dc as Dc, x as Number, y as Number, text as String, pitch as Number) as Void {
        var dot = pitch - 1;
        var chars = text.toCharArray();
        var cx = x;
        for (var i = 0; i < chars.size(); i++) {
            var ch = chars[i];
            if (ch == ':') {
                dc.fillRectangle(cx, y + 2 * pitch, dot, dot);
                dc.fillRectangle(cx, y + 4 * pitch, dot, dot);
                cx += dot + pitch;
            } else if (ch == '-') {
                dc.fillRectangle(cx + pitch, y + 3 * pitch, 3 * pitch - 1, dot);
                cx += DIGIT_COLS * pitch - 1 + pitch;
            } else {
                var glyph = DIGITS[ch.toNumber() - 48] as Array<Number>;
                for (var r = 0; r < DIGIT_ROWS; r++) {
                    var bits = glyph[r];
                    for (var c = 0; c < DIGIT_COLS; c++) {
                        if ((bits & (0x10 >> c)) != 0) {
                            dc.fillRectangle(cx + c * pitch, y + r * pitch, dot, dot);
                        }
                    }
                }
                cx += DIGIT_COLS * pitch - 1 + pitch;
            }
        }
    }

    // --- data -------------------------------------------------------------

    private function currentHeartRate() as Number? {
        var info = Activity.getActivityInfo();
        if (info != null && info.currentHeartRate != null) {
            return info.currentHeartRate;
        }
        if (ActivityMonitor has :getHeartRateHistory) {
            var it = ActivityMonitor.getHeartRateHistory(1, true);
            if (it != null) {
                var sample = it.next();
                if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                    return sample.heartRate;
                }
            }
        }
        return null;
    }

    private function formatSteps(steps as Number) as String {
        if (steps >= 10000) {
            return (steps / 1000).format("%d") + "k";
        }
        if (steps >= 1000) {
            return (steps / 1000.0).format("%.1f") + "k";
        }
        return steps.format("%d");
    }
}
