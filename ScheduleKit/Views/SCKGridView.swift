/*
 *  SCKGridView.swift
 *  ScheduleKit
 *
 *  Created:    Guillem Servera on 28/10/2016.
 *  Copyright:  © 2016-2019 Guillem Servera (https://github.com/gservera)
 *
 *  Permission is hereby granted, free of charge, to any person obtaining a copy
 *  of this software and associated documentation files (the "Software"), to deal
 *  in the Software without restriction, including without limitation the rights
 *  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 *  copies of the Software, and to permit persons to whom the Software is
 *  furnished to do so, subject to the following conditions:
 *
 *  The above copyright notice and this permission notice shall be included in
 *  all copies or substantial portions of the Software.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 *  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 *  THE SOFTWARE.
 */

import Cocoa

/// An object conforming to the `SCKGridViewDelegate` protocol may implement a
/// method to provide unavailable time ranges to a grid-style schedule view in
/// addition to other methods defined in `SCKViewDelegate`.
@objc public protocol SCKGridViewDelegate: SCKViewDelegate {

    /// Implement this method to specify the first displayed hour. Defaults to 0.
    /// - Parameter gridView: The grid view asking for a start hour.
    /// - Returns: An hour value from 0 to 24.
    @objc(dayStartHourForGridView:) func dayStartHour(for gridView: SCKGridView) -> Int

    /// Implement this method to specify the last displayed hour. Defaults to 24.
    /// - Parameter gridView: The grid view asking for a start hour.
    /// - Returns: An hour value from 0 to 24, where 0 is parsed as 24.
    @objc(dayEndHourForGridView:) func dayEndHour(for gridView: SCKGridView) -> Int

    /// Implemented by a grid-style schedule view's delegate to provide an array
    /// of unavailable time ranges that are drawn as so by the view.
    /// - Parameter gridView: The schedule view asking for the values.
    /// - Returns: The array of unavailable time ranges (may be empty).
    @objc(unavailableTimeRangesForGridView:)
    optional func unavailableTimeRanges(for gridView: SCKGridView) -> [SCKUnavailableTimeRange]
}

/// An abstract `SCKView` subclass that implements the common functionality of any
/// grid-style schedule view, such as the built in day view and week view. This 
/// class provides conflict management, interaction with the displayed days and 
/// hours, displaying unavailable time intervals and a zoom feature. 
///
/// It also manages a series of day, month, hour and hour fraction labels, which 
/// are automatically updated and laid out by this class.
/// - Note: Do not instantiate this class directly.
public class SCKGridView: SCKView {

    struct Constants {
        static let DayAreaHeight: CGFloat = 40.0
        static let DayAreaMarginBottom: CGFloat = 20.0
        static let MaxHeightPerHour: CGFloat = 300.0
        static let HourAreaWidth: CGFloat = 56.0
        static var paddingTop: CGFloat { return DayAreaHeight + DayAreaMarginBottom }
    }

    override func setUp() {
        super.setUp()
        updateHourParameters()
    }

    override public weak var delegate: SCKViewDelegate? {
        didSet {
            readDefaultsFromDelegate()
        }
    }

    // MARK: - Date handling additions

    public override var dateInterval: DateInterval {
        didSet { // Set up day count and day labels
            let sDate = dateInterval.start
            let eDate = dateInterval.end.addingTimeInterval(1)
            dayCount = sharedCalendar.dateComponents([.day], from: sDate, to: eDate).day!
            dayLabelingView.configure(dayCount: dayCount, startDate: sDate)
            _ = self.minuteTimer
        }
    }

    /// The number of days displayed. Updated by changing `dateInterval`.
    private(set) var dayCount: Int = 0

    /// A value representing the day start hour.
    private var dayStartPoint = SCKDayPoint.zero

    /// A view representign the day end hour.
    private var dayEndPoint = SCKDayPoint(hour: 24, minute: 0, second: 0)

    /// Called when the `dayStartPoint` and `dayEndPoint` change during  initialisation
    /// or when their values are read from the delegate. Sets the `firstHour` and
    /// `hourCount` properties and ensures a minimum height per hour to fill the view.
    private func updateHourParameters() {
        firstHour = dayStartPoint.hour
        hourCount = dayEndPoint.hour - dayStartPoint.hour
        let minHourHeight = contentRect.height / CGFloat(hourCount)
        if hourHeight < minHourHeight {
            hourHeight = minHourHeight
        }
    }

    /// The first hour of the day displayed.
    internal var firstHour: Int = 0 {
        didSet { hourLabelingView.configureHourLabels(firstHour: firstHour, hourCount: hourCount) }
    }

    /// The total number of hours displayed.
    internal var hourCount: Int = 1 {
        didSet { hourLabelingView.configureHourLabels(firstHour: firstHour, hourCount: hourCount) }
    }

    /// The height for each hour row. Setting this value updates the saved one in
    /// UserDefaults and updates hour labels visibility.
    internal var hourHeight: CGFloat = 0.0 {
        didSet {
            if hourHeight != oldValue && superview != nil {
                let key = SCKGridView.defaultsZoomKeyPrefix + ".\(type(of: self))"
                UserDefaults.standard.set(hourHeight, forKey: key)
                invalidateIntrinsicContentSize()
            }
            hourLabelingView.updateHourLabelsVisibility(hourHeight: hourHeight,
                                                        eventViewBeingDragged: eventViewBeingDragged)
        }
    }

    // MARK: Day and month labels

    /// A container view for day labels. Pinned at the top of the scroll view.
    private let dayLabelingView = SCKDayLabelingView(frame: CGRect(x: 0, y: 0, width: 0, height: Constants.DayAreaHeight))

    /// A container view for hour labels. Pinned left in the scroll view.
    private let hourLabelingView = SCKHourLabelingView(frame: .zero)

    // MARK: - Date transform additions

    override func relativeTimeLocation(for point: CGPoint) -> Double {
        if contentRect.contains(point) {
            let dayWidth: CGFloat = contentRect.width / CGFloat(dayCount)
            let offsetPerDay = 1.0 / Double(dayCount)
            let day = Int(trunc((point.x-contentRect.minX)/dayWidth))
            let dayOffset = offsetPerDay * Double(day)
            let offsetPerMin = calculateRelativeTimeLocation(for: dateInterval.start.addingTimeInterval(60))
            let offsetPerHour = 60.0 * offsetPerMin
            let totalMinutes = 60.0 * CGFloat(hourCount)
            let minute = totalMinutes * (point.y - contentRect.minY) / contentRect.height
            let minuteOffset = offsetPerMin * Double(minute)
            return dayOffset + offsetPerHour * Double(firstHour) + minuteOffset
        }
        return SCKRelativeTimeLocationInvalid
    }

    /// Returns the Y-axis position in the view's coordinate system that represents a particular hour and
    /// minute combination.
    /// - Parameters:
    ///   - hour: The hour.
    ///   - minute: The minute.
    /// - Returns: The calculated Y position.
    internal func yFor(hour: Int, minute: Int) -> CGFloat {
        let canvas = contentRect
        let hours = CGFloat(hourCount)
        let hourIndex = CGFloat(hour - firstHour)
        return canvas.minY + canvas.height * (hourIndex + CGFloat(minute)/60.0) / hours
    }

    // MARK: - Event Layout overrides

    override public var contentRect: CGRect {
        // Exclude day and hour labeling areas.
        return CGRect(x: Constants.HourAreaWidth, y: Constants.paddingTop,
                      width: frame.width - Constants.HourAreaWidth,
                      height: CGFloat(hourCount) * hourHeight)
    }

    override func invalidateLayout(for eventView: SCKEventView) {
        // Overriden to manage event conflicts. No need to call super in this case.
        let conflicts = controller.resolvedConflicts(for: eventView.eventHolder)
        if !conflicts.isEmpty {
            eventView.eventHolder.conflictCount = conflicts.count
        } else {
            eventView.eventHolder.conflictCount = 1 //FIXME: Should not get here.
            NSLog("Unexpected behavior")
        }
        eventView.eventHolder.conflictIndex = conflicts.firstIndex(where: { $0 === eventView.eventHolder }) ?? 0
    }

    override func prepareForDragging() {
        hourLabelingView.updateHourLabelsVisibility(hourHeight: hourHeight,
                                                    eventViewBeingDragged: eventViewBeingDragged)
        super.prepareForDragging()
    }

    override func restoreAfterDragging() {
        hourLabelingView.updateHourLabelsVisibility(hourHeight: hourHeight,
                                                    eventViewBeingDragged: eventViewBeingDragged)
        super.restoreAfterDragging()
    }

    // MARK: - NSView overrides

    public override var intrinsicContentSize: NSSize {
        return CGSize(width: NSView.noIntrinsicMetric, height: CGFloat(hourCount) * hourHeight + Constants.paddingTop)
    }

    public override func removeFromSuperview() {
        dayLabelingView.removeFromSuperview()
        super.removeFromSuperview()
    }

    public override func updateConstraints() {
        let marginLeft = Constants.HourAreaWidth
        let dayLabelsRect = CGRect(x: marginLeft, y: 0, width: frame.width-marginLeft, height: Constants.DayAreaHeight)
        let dayWidth = dayLabelsRect.width / CGFloat(dayCount)

        // Layout events
        let offsetPerDay = 1.0/Double(dayCount)
        for eventView in subviews.compactMap({ $0 as? SCKEventView }) where eventView.eventHolder.isReady {
            let holder = eventView.eventHolder!
            let day = Int(trunc(holder.relativeStart/offsetPerDay))
            let sPoint = SCKDayPoint(date: holder.cachedScheduledDate)
            let eMinute = sPoint.minute + holder.cachedDuration
            let ePoint = SCKDayPoint(hour: sPoint.hour, minute: eMinute, second: sPoint.second)
            let top = yFor(hour: sPoint.hour, minute: sPoint.minute)
            eventView.topConstraint.constant = top
            eventView.heightConstraint.constant = yFor(hour: ePoint.hour, minute: ePoint.minute)-top
            let width = dayWidth / CGFloat(eventView.eventHolder.conflictCount)
            eventView.widthConstraint.constant = width
            eventView.leadingConstraint.constant = Constants.HourAreaWidth + CGFloat(day) * dayWidth + width * CGFloat(holder.conflictIndex)
            NSLayoutConstraint.activate([
                eventView.topConstraint, eventView.leadingConstraint,
                eventView.widthConstraint, eventView.heightConstraint
            ])
        }
        super.updateConstraints()
    }

    public override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize) // Triggers layout. Try to acommodate hour height.
        let visibleHeight = superview!.frame.height - Constants.paddingTop
        let contentHeight = CGFloat(hourCount) * hourHeight
        if contentHeight < visibleHeight && hourCount > 0 {
            hourHeight = visibleHeight / CGFloat(hourCount)
        }
        dayLabelingView.needsUpdateConstraints = true
        hourLabelingView.needsUpdateConstraints = true
        needsUpdateConstraints = true
    }

    public override func viewWillMove(toSuperview newSuperview: NSView?) {
        // Insert day labeling view
        guard let superview = newSuperview else { return }
        let height = Constants.DayAreaHeight
        if let parent = superview.superview?.superview {
            dayLabelingView.translatesAutoresizingMaskIntoConstraints = false
            parent.addSubview(dayLabelingView, positioned: .above, relativeTo: nil)
            NSLayoutConstraint.activate([
                dayLabelingView.leftAnchor.constraint(equalTo: parent.leftAnchor, constant: Constants.HourAreaWidth),
                dayLabelingView.rightAnchor.constraint(equalTo: parent.rightAnchor),
                dayLabelingView.topAnchor.constraint(equalTo: parent.topAnchor),
                dayLabelingView.heightAnchor.constraint(equalToConstant: height)
            ])
            hourLabelingView.translatesAutoresizingMaskIntoConstraints = false
            hourLabelingView.paddingTop = Constants.DayAreaMarginBottom
            addSubview(hourLabelingView, positioned: .above, relativeTo: nil)
            NSLayoutConstraint.activate([
                hourLabelingView.leftAnchor.constraint(equalTo: leftAnchor),
                hourLabelingView.widthAnchor.constraint(equalToConstant: Constants.HourAreaWidth),
                hourLabelingView.topAnchor.constraint(equalTo: topAnchor, constant: Constants.DayAreaHeight)
            ])
        }
        DispatchQueue.main.asyncAfter(deadline: .now()) { [weak self] in
            self?.dayLabelingView.needsUpdateConstraints = true
        }
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard superview != nil else { return } // Called when removed
        // Restore zoom if possible
        let zoomKey = SCKGridView.defaultsZoomKeyPrefix + ".\(String(describing: type(of: self)))"
        let hHeight = CGFloat(UserDefaults.standard.double(forKey: zoomKey))
        processNewHourHeight(hHeight)
    }

    // MARK: - Delegate defaults

    /// Calls some of the delegate methods to reflect user preferences. The default implementation asks for
    /// unavailable time ranges and day start/end hours. Subclasses may override this method to set up additional
    /// parameters by importing settings from their delegate objects. This method is called when the view is set
    /// up and when the `invalidateUserDefaults()` method is called. You should not call this method directly.
    internal func readDefaultsFromDelegate() {
        guard let delegate = delegate as? SCKGridViewDelegate else { return }
        if let unavailableRanges = delegate.unavailableTimeRanges?(for: self) {
            unavailableTimeRanges = unavailableRanges
            needsDisplay = true
        }
        let start = delegate.dayStartHour(for: self)
        var end = delegate.dayEndHour(for: self)
        if end == 0 { end = 24 }
        dayStartPoint = SCKDayPoint(hour: start, minute: 0, second: 0)
        dayEndPoint = SCKDayPoint(hour: end, minute: 0, second: 0)
        updateHourParameters()
        invalidateIntrinsicContentSize()
        invalidateLayoutForAllEventViews()
    }

    /// Makes the view update some of its parameters, such as the unavailable time
    /// ranges by reflecting the values supplied by the delegate.
    @objc public final func invalidateUserDefaults() {
        readDefaultsFromDelegate()
    }

    // MARK: - Unavailable time ranges

    /// The time ranges that should be drawn as unavailable in this view.
    private var unavailableTimeRanges: [SCKUnavailableTimeRange] = []

    /// Calculates the rect to be drawn as unavailable from a given unavailable time range.
    /// - Parameter rng: The unavailable time range.
    /// - Returns: The calcualted rect.
    func rectForUnavailableTimeRange(_ rng: SCKUnavailableTimeRange) -> CGRect {
        let canvas = contentRect
        let dayWidth: CGFloat = canvas.width / CGFloat(dayCount)
        let sDate = sharedCalendar.date(bySettingHour: rng.startHour, minute: rng.startMinute, second: 0,
                                        of: dateInterval.start)!
        let sOffset = calculateRelativeTimeLocation(for: sDate)
        if sOffset != SCKRelativeTimeLocationInvalid {
            let endSeconds = rng.endMinute * 60 + rng.endHour * 3600
            let startSeconds = rng.startMinute * 60 + rng.startHour * 3600
            let eDate = sDate.addingTimeInterval(Double(endSeconds - startSeconds))
            let yOrigin = yFor(hour: rng.startHour, minute: rng.startMinute)
            var yLength: CGFloat = frame.maxY - yOrigin // Assuming SCKRelativeTimeLocationInvalid for eDate
            if calculateRelativeTimeLocation(for: eDate) != SCKRelativeTimeLocationInvalid {
                yLength = yFor(hour: rng.endHour, minute: rng.endMinute) - yOrigin
            }
            let weekday = (rng.weekday == -1) ? 0.0 : CGFloat(rng.weekday)
            return CGRect(x: canvas.minX + weekday * dayWidth, y: yOrigin, width: dayWidth, height: yLength)
        }
        return .zero
    }

    // MARK: - Minute timer

    /// A timer that fires every minute to mark the view as needing display in order to update the "now" line.
    private lazy var minuteTimer: Timer = {
        let sel = #selector(SCKGridView.minuteTimerFired(timer:))
        let tmr = Timer.scheduledTimer(timeInterval: 60.0, target: self, selector: sel, userInfo: nil, repeats: true)
        tmr.tolerance = 50.0
        return tmr
    }()

    @objc dynamic func minuteTimerFired(timer: Timer) {
        needsDisplay = true
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard hourCount > 0 else { return }
        drawUnavailableTimeRanges()
        drawDayDelimiters()
        drawHourDelimiters()
        drawCurrentTimeLine()
        drawDraggingGuidesIfNeeded()
    }

    private func drawUnavailableTimeRanges() {
        NSColor.windowBackgroundColor.set()
        unavailableTimeRanges.forEach { rectForUnavailableTimeRange($0).fill() }
    }

    private func drawDayDelimiters() {
        let canvas = CGRect(x: Constants.HourAreaWidth, y: Constants.DayAreaHeight,
                            width: frame.width-Constants.HourAreaWidth, height: frame.height-Constants.DayAreaHeight)
        let dayWidth = canvas.width / CGFloat(dayCount)
        NSColor.gridColor.set()
        for day in 0..<dayCount {
            CGRect(x: canvas.minX + CGFloat(day) * dayWidth, y: canvas.minY, width: 1.0, height: canvas.height).fill()
        }
    }

    private func drawHourDelimiters() {
        NSColor.gridColor.set()
        for hour in 0..<hourCount {
            CGRect(x: contentRect.minX-8.0, y: contentRect.minY + CGFloat(hour) * hourHeight - 0.4,
                   width: contentRect.width + 8.0, height: 1.0).fill()
        }
    }

    private func drawCurrentTimeLine() {
        let canvas = contentRect
        let components = sharedCalendar.dateComponents([.hour, .minute], from: Date())
        let minuteCount = Double(hourCount) * 60.0
        let elapsedMinutes = Double(components.hour!-firstHour) * 60.0 + Double(components.minute!)
        let yOrigin = canvas.minY + canvas.height * CGFloat(elapsedMinutes / minuteCount)
        NSColor.systemRed.setFill()
        CGRect(x: canvas.minX, y: yOrigin-0.5, width: canvas.width, height: 1.0).fill()
        NSBezierPath(ovalIn: CGRect(x: canvas.minX-2.0, y: yOrigin-2.0, width: 4.0, height: 4.0)).fill()
    }

    private func drawDraggingGuidesIfNeeded() {
        guard let dView = eventViewBeingDragged else { return }
        (dView.backgroundColor ?? NSColor.darkGray).setFill()

        let canvas = contentRect
        let dragFrame = dView.frame

        // Left, right, top and bottom guides
        CGRect.fill(canvas.minX, dragFrame.midY-1.0, dragFrame.minX-canvas.minX, 2.0)
        CGRect.fill(dragFrame.maxX, dragFrame.midY-1.0, frame.width-dragFrame.maxX, 2.0)
        CGRect.fill(dragFrame.midX-1.0, canvas.minY, 2.0, dragFrame.minY-canvas.minY)
        CGRect.fill(dragFrame.midX-1.0, dragFrame.maxY, 2.0, frame.height-dragFrame.maxY)

        let dayWidth = canvas.width / CGFloat(dayCount)
        let offsetPerDay = 1.0/Double(dayCount)
        let startOffset = relativeTimeLocation(for: CGPoint(x: dragFrame.midX, y: dragFrame.minY))
        if startOffset != SCKRelativeTimeLocationInvalid {
            CGRect.fill(canvas.minX + dayWidth * CGFloat(trunc(startOffset/offsetPerDay)), canvas.minY, dayWidth, 2.0)
            let startDate = calculateDate(for: startOffset)!
            let sPoint = SCKDayPoint(date: startDate)
            let ePoint = SCKDayPoint(date: startDate.addingTimeInterval(Double(dView.eventHolder.cachedDuration)*60.0))
            let sLabelText = NSString(format: "%ld:%02ld", sPoint.hour, sPoint.minute)
            let eLabelText = NSString(format: "%ld:%02ld", ePoint.hour, ePoint.minute)
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.darkGray,
                .font: NSFont.systemFont(ofSize: 12.0)
            ]
            let sLabelSize = sLabelText.size(withAttributes: attrs)
            let eLabelSize = eLabelText.size(withAttributes: attrs)
            let sLabelRect = CGRect(x: Constants.HourAreaWidth/2.0-sLabelSize.width/2.0,
                                    y: dragFrame.minY-sLabelSize.height/2.0,
                                    width: sLabelSize.width, height: sLabelSize.height)
            let eLabelRect = CGRect(x: Constants.HourAreaWidth/2.0-eLabelSize.width/2.0,
                                    y: dragFrame.maxY-eLabelSize.height/2.0,
                                    width: eLabelSize.width, height: eLabelSize.height)
            sLabelText.draw(in: sLabelRect, withAttributes: attrs)
            eLabelText.draw(in: eLabelRect, withAttributes: attrs)
            let durationText = "\(dView.eventHolder.cachedDuration) min"
            let dLabelSize = durationText.size(withAttributes: attrs)
            let durationRect = CGRect(x: Constants.HourAreaWidth/2.0-dLabelSize.width/2.0,
                                      y: dragFrame.midY-dLabelSize.height/2.0,
                                      width: dLabelSize.width, height: dLabelSize.height)
            durationText.draw(in: durationRect, withAttributes: attrs)
        }
    }
}

// MARK: - Hour height and zoom

extension SCKGridView {

    /// A prefix appended to the class name to work as a key to store last zoom level for each subclass in user defaults
    private static let defaultsZoomKeyPrefix = "MEKZoom"

    /// Increases the hour height property if less than the maximum value. Marks the view as needing display.
    func increaseZoomFactor() {
        processNewHourHeight(hourHeight + 8.0)
    }

    /// Decreases the hour height property if greater than the minimum value. Marks the view as needing display.
    func decreaseZoomFactor() {
        processNewHourHeight(hourHeight - 8.0)
    }

    public override func magnify(with event: NSEvent) {
        processNewHourHeight(hourHeight + 16.0 * event.magnification)
    }

    /// Increases or decreases the hour height property if greater than the minimum value and less than the maximum
    /// hour height. Marks the view as needing display.
    /// - Parameter targetHeight: The calculated new hour height.
    private func processNewHourHeight(_ targetHeight: CGFloat) {
        defer {
            needsDisplay = true
            needsUpdateConstraints = true
        }
        guard targetHeight < Constants.MaxHeightPerHour else {
            hourHeight = Constants.MaxHeightPerHour
            return
        }
        let minimumContentHeight = superview!.frame.height - Constants.paddingTop
        if targetHeight * CGFloat(hourCount) >= minimumContentHeight {
            hourHeight = targetHeight
        } else {
            hourHeight = minimumContentHeight / CGFloat(hourCount)
        }
    }
}
