/*
 * Copyright (c) 2013-2014 Meltytech, LLC
 * Author: Dan Dennedy <dan@dennedy.org>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.0
import QtQml.Models 2.1
import 'Track.js' as Logic

Rectangle {
    id: trackRoot
    property alias model: trackModel.model
    property alias rootIndex: trackModel.rootIndex
    property bool isAudio
    property real timeScale: 1.0
    property bool placeHolderAdded: false

    signal clipSelected(var clip, var track)
    signal clipDragged(var clip, int x, int y)
    signal clipDropped(var clip)
    signal clipDraggedToTrack(var clip, int direction)
    signal checkSnap(var clip)

    function resetStates(index) {
        for (var i = 0; i < repeater.count; i++)
            if (i !== index) repeater.itemAt(i).state = ''
    }

    function redrawWaveforms() {
        for (var i = 0; i < repeater.count; i++)
            repeater.itemAt(i).generateWaveform()
    }

    function snapClip(clip) {
        Logic.snapClip(clip, repeater)
    }

    function snapDrop(clip) {
        Logic.snapDrop(clip, repeater)
    }

    color: 'transparent'

    DelegateModel {
        id: trackModel
        Clip {
            clipName: model.name
            clipResource: model.resource
            clipDuration: model.duration
            mltService: model.mlt_service
            inPoint: model.in
            outPoint: model.out
            isBlank: model.blank
            isAudio: model.audio
            isTransition: model.isTransition
            audioLevels: model.audioLevels
            width: model.duration * timeScale
            height: trackRoot.height
            trackIndex: trackRoot.DelegateModel.itemsIndex
            fadeIn: model.fadeIn
            fadeOut: model.fadeOut

            onSelected: {
                resetStates(clip.DelegateModel.itemsIndex);
                trackRoot.clipSelected(clip, trackRoot);
            }
            onMoved: {
                var fromTrack = clip.originalTrackIndex
                var toTrack = clip.trackIndex
                var clipIndex = clip.originalClipIndex
                var frame = Math.round(clip.x / timeScale)

                // Remove the placeholder inserted in onDraggedToTrack
                if (placeHolderAdded) {
                    placeHolderAdded = false
                    if (fromTrack === toTrack)
                        // XXX This is causing timeline to become undefined making function
                        // call below to fail. This basically results in rejected operation
                        // to the user, but at least it prevents the timeline from becoming
                        // corrupt and out-of-sync with the model.
                        trackModel.items.resolve(clipIndex, clipIndex + 1)
                    else
                        trackModel.items.remove(clipIndex, 1)
                }
                if (!timeline.moveClip(fromTrack, toTrack, clipIndex, frame))
                    clip.x = clip.originalX
            }
            onDragged: {
                // Snap if Alt key is not down.
                if (toolbar.scrub)
                    timeline.position = Math.round(clip.x / timeScale)
                if (!(mouse.modifiers & Qt.AltModifier) && toolbar.snap)
                    trackRoot.checkSnap(clip)
                var mapped = trackRoot.mapFromItem(clip, mouse.x, mouse.y)
                trackRoot.clipDragged(clip, mapped.x, mapped.y)
            }
            onTrimmingIn: {
                if (!(mouse.modifiers & Qt.AltModifier) && toolbar.snap)
                    delta = Logic.snapTrimIn(clip, delta)
                if (delta != 0) {
                    timeline.trimClipIn(trackRoot.DelegateModel.itemsIndex, clip.DelegateModel.itemsIndex, delta)

                    // Show amount trimmed as a time in a "bubble" help.
                    var s = timeline.timecode(Math.abs(clip.originalX))
                    s = '%1%2 = %3'.arg((clip.originalX < 0)? '-' : (clip.originalX > 0)? '+' : '')
                                   .arg(s.substring(3))
                                   .arg(timeline.timecode(clipDuration))
                    bubbleHelp.show(clip.x, trackRoot.y + trackRoot.height, s)
                }
            }
            onTrimmedIn: {
                multitrack.notifyClipIn(trackRoot.DelegateModel.itemsIndex, clip.DelegateModel.itemsIndex)
                bubbleHelp.hide()
            }
            onTrimmingOut: {
                if (!(mouse.modifiers & Qt.AltModifier) && toolbar.snap)
                    delta = Logic.snapTrimOut(clip, delta)
                if (delta != 0) {
                    timeline.trimClipOut(trackRoot.DelegateModel.itemsIndex, clip.DelegateModel.itemsIndex, delta)

                    // Show amount trimmed as a time in a "bubble" help.
                    var s = timeline.timecode(Math.abs(clip.originalX))
                    s = '%1%2 = %3'.arg((clip.originalX < 0)? '+' : (clip.originalX > 0)? '-' : '')
                                   .arg(s.substring(3))
                                   .arg(timeline.timecode(clipDuration))
                    bubbleHelp.show(clip.x + clip.width, trackRoot.y + trackRoot.height, s)
                }
            }
            onTrimmedOut: {
                multitrack.notifyClipOut(trackRoot.DelegateModel.itemsIndex, clip.DelegateModel.itemsIndex)
                bubbleHelp.hide()
            }
            onDraggedToTrack: {
                if (!placeHolderAdded) {
                    placeHolderAdded = true
                    trackModel.items.insert(clip.DelegateModel.itemsIndex, {
                        'name': '',
                        'resource': '',
                        'duration': clip.clipDuration,
                        'mlt_service': '<producer',
                        'in': 0,
                        'out': clip.clipDuration - 1,
                        'blank': true,
                        'audio': false,
                        'fadeIn': 0,
                        'fadeOut': 0
                    })
                }
            }
            onDropped: placeHolderAdded = false

            Component.onCompleted: {
                moved.connect(trackRoot.clipDropped)
                dropped.connect(trackRoot.clipDropped)
                draggedToTrack.connect(trackRoot.clipDraggedToTrack)
            }
        }
    }

    Row {
        Repeater { id: repeater; model: trackModel }
    }
}
