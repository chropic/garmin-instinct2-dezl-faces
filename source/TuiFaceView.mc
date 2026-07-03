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
//   [TIME]  panel, top-left, beside the subscreen
//   (HR)    inside the physical subscreen circle
//   [DATE]  full-width panel:  FRI 2026-07-03
//   [SYS]   full-width panel:  BAT / STP segment meters
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
        var fullW = width - 2 * MARGIN;
        var xtinyH = dc.getFontHeight(Graphics.FONT_XTINY);
        var tinyH = dc.getFontHeight(Graphics.FONT_TINY);

        var subBottom = _subY + _subH;
        var timeW = _subX - GAP - MARGIN;
        var timeH = subBottom - PANEL_TOP;

        var dateY = subBottom + GAP;
        var dateH = tinyH + 6;

        var sysY = dateY + dateH + GAP;
        var sysH = 2 * (xtinyH + 2) + 8;

        drawTimePanel(dc, MARGIN, PANEL_TOP, timeW, timeH);
        drawSubscreenHr(dc);
        drawDatePanel(dc, MARGIN, dateY, fullW, dateH);
        drawSysPanel(dc, MARGIN, sysY, fullW, sysH);
        drawPrompt(dc, width / 2, sysY + sysH + 2);
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

        var font = pickLargestFont(dc, timeStr, w - 8, h - 12);
        dc.drawText(x + w / 2, y + h / 2, font, timeStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

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
        dc.drawText(cx, cy + 6, Graphics.FONT_MEDIUM, hrStr,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
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

    private function drawSysPanel(dc as Dc, x as Number, y as Number, w as Number, h as Number) as Void {
        drawPanel(dc, x, y, w, h, "SYS");

        var xtinyH = dc.getFontHeight(Graphics.FONT_XTINY);
        var rowX = x + 5;
        var rowW = w - 10;
        var row1Y = y + 5;
        var row2Y = row1Y + xtinyH + 2;

        var stats = System.getSystemStats();
        var battery = stats.battery;
        var batRatio = (battery == null) ? 0.0 : battery / 100.0;
        var batStr = (battery == null) ? "--" : battery.toNumber().format("%d") + "%";
        drawMeterRow(dc, rowX, row1Y, rowW, "BAT", batRatio, batStr);

        var info = ActivityMonitor.getInfo();
        var steps = info.steps;
        var goal = info.stepGoal;
        var stepRatio = 0.0;
        if (steps != null && goal != null && goal > 0) {
            stepRatio = steps.toFloat() / goal;
        }
        var stepStr = (steps == null) ? "--" : formatSteps(steps);
        drawMeterRow(dc, rowX, row2Y, rowW, "STP", stepRatio, stepStr);
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

    // Segmented meter: label, [####----] bar, right-aligned value.
    private function drawMeterRow(dc as Dc, x as Number, y as Number, w as Number, label as String, ratio as Float, value as String) as Void {
        var font = Graphics.FONT_XTINY;
        var fh = dc.getFontHeight(font);
        var labelW = dc.getTextWidthInPixels(label + " ", font);
        var valueW = dc.getTextWidthInPixels("12.3k", font);

        dc.drawText(x, y, font, label, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(x + w, y, font, value, Graphics.TEXT_JUSTIFY_RIGHT);

        var barX = x + labelW;
        var barW = w - labelW - valueW - 6;
        var barH = fh - 6;
        if (barH < 6) {
            barH = 6;
        }
        drawMeter(dc, barX, y + (fh - barH) / 2, barW, barH, ratio);
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

    private function pickLargestFont(dc as Dc, text as String, maxW as Number, maxH as Number) as FontDefinition {
        var candidates = [
            Graphics.FONT_NUMBER_HOT,
            Graphics.FONT_NUMBER_MEDIUM,
            Graphics.FONT_NUMBER_MILD,
            Graphics.FONT_LARGE,
            Graphics.FONT_MEDIUM,
            Graphics.FONT_SMALL
        ];
        for (var i = 0; i < candidates.size(); i++) {
            var font = candidates[i];
            if (dc.getTextWidthInPixels(text, font) <= maxW
                && dc.getFontHeight(font) <= maxH) {
                return font;
            }
        }
        return Graphics.FONT_XTINY;
    }
}
