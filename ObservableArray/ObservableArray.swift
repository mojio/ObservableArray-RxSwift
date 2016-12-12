//
//  ObservableArray.swift
//  ObservableArray
//
//  Created by Safx Developer on 2015/02/19.
//  Copyright (c) 2016 Safx Developers. All rights reserved.
// 
//

import Foundation
import RxSwift

public struct ArrayChangeEvent {
    public let insertedIndices: [Int]
    public let deletedIndices: [Int]
    public let updatedIndices: [Int]

    private init(inserted: [Int] = [], deleted: [Int] = [], updated: [Int] = []) {
        assert(inserted.count + deleted.count + updated.count > 0)
        self.insertedIndices = inserted
        self.deletedIndices = deleted
        self.updatedIndices = updated
    }
}

public struct ObservableArray<Element>: ArrayLiteralConvertible {
    public typealias EventType = ArrayChangeEvent

    internal let lockUpdateQueue = dispatch_queue_create(nil, DISPATCH_QUEUE_SERIAL)
    internal var eventSubject: PublishSubject<EventType>!
    internal var elementsSubject: BehaviorSubject<[Element]>!
    internal var elements: [Element]

    public init() {
        self.elements = []
    }

    public init(count:Int, repeatedValue: Element) {
        self.elements = Array(count: count, repeatedValue: repeatedValue)
    }

    public init<S : SequenceType where S.Generator.Element == Element>(_ s: S) {
        self.elements = Array(s)
    }

    public init(arrayLiteral elements: Element...) {
        self.elements = elements
    }
}

extension ObservableArray {
    public func getlockUpdateQueue() -> dispatch_queue_t {
        return self.lockUpdateQueue
    }
}

extension ObservableArray {
    public mutating func rx_elements() -> Observable<[Element]> {
        
        dispatch_sync(self.lockUpdateQueue) {
            if elementsSubject == nil {
                self.elementsSubject = BehaviorSubject<[Element]>(value: self.elements)
            }
        }
        
        return elementsSubject
    }

    public mutating func rx_events() -> Observable<EventType> {
        
        dispatch_sync(self.lockUpdateQueue) {
            if eventSubject == nil {
                self.eventSubject = PublishSubject<EventType>()
            }
        }

        return eventSubject
    }

    private func arrayDidChange(event: EventType) {
        elementsSubject?.onNext(elements)
        eventSubject?.onNext(event)
    }
}

extension ObservableArray: Indexable {
    public var startIndex: Int {
        return elements.startIndex
    }

    public var endIndex: Int {
        return elements.endIndex
    }
}

extension ObservableArray: RangeReplaceableCollectionType {
    public var capacity: Int {
        return elements.capacity
    }

    public mutating func reserveCapacity(minimumCapacity: Int) {
        dispatch_sync(self.lockUpdateQueue) {
            elements.reserveCapacity(minimumCapacity)
        }
    }

    public mutating func append(newElement: Element) {
        var inserted: [Int] = []
        
        dispatch_sync(self.lockUpdateQueue) {
            elements.append(newElement)
            inserted = [elements.count - 1]
        }

        arrayDidChange(ArrayChangeEvent(inserted: inserted))
    }

    public mutating func appendContentsOf<S : SequenceType where S.Generator.Element == Element>(newElements: S) {
        var inserted: [Int] = []
        
        dispatch_sync(self.lockUpdateQueue) {
            let end = elements.count
            elements.appendContentsOf(newElements)
            guard end != elements.count else {
                return
            }

            inserted = Array(end..<elements.count)
        }

        arrayDidChange(ArrayChangeEvent(inserted: inserted))
    }

    public mutating func appendContentsOf<C : CollectionType where C.Generator.Element == Element>(newElements: C) {
        guard !newElements.isEmpty else {
            return
        }
        
        var inserted: [Int] = []
        
        dispatch_sync(self.lockUpdateQueue) {
            let end = elements.count
            elements.appendContentsOf(newElements)
            inserted = Array(end..<elements.count)
        }
        
        arrayDidChange(ArrayChangeEvent(inserted: inserted))
    }

    public mutating func removeLast() -> Element {
        var e: Element? = nil
        var deleted: [Int] = []
        
        dispatch_sync(self.lockUpdateQueue) {
            e = elements.removeLast()
            deleted = [elements.count]
        }

        arrayDidChange(ArrayChangeEvent(deleted: deleted))
        
        // Item must exist
        return e! as Element
    }

    public mutating func insert(newElement: Element, atIndex i: Int) {
        var inserted: [Int] = []

        dispatch_sync(self.lockUpdateQueue) {
            elements.insert(newElement, atIndex: i)
            inserted = [i]
        }

        arrayDidChange(ArrayChangeEvent(inserted: inserted))
    }

    public mutating func removeAtIndex(index: Int) -> Element {
        var e: Element? = nil
        var deleted: [Int] = []

        dispatch_sync(self.lockUpdateQueue) {
            e = elements.removeAtIndex(index)
            deleted = [index]
        }
        
        arrayDidChange(ArrayChangeEvent(deleted: deleted))
        
        // Item must exist
        return e! as Element
    }

    public mutating func removeAll(keepCapacity: Bool = false) {
        guard !elements.isEmpty else {
            return
        }
        
        var deleted: [Int] = []
        
        dispatch_sync(self.lockUpdateQueue) {
            let es = elements
            elements.removeAll(keepCapacity: keepCapacity)
            deleted = Array(0..<es.count)
        }

        arrayDidChange(ArrayChangeEvent(deleted: deleted))
    }

    public mutating func insertContentsOf(newElements: [Element], atIndex i: Int) {
        guard !newElements.isEmpty else {
            return
        }
        
        var inserted: [Int] = []
        
        dispatch_sync(self.lockUpdateQueue) {
            elements.insertContentsOf(newElements, at: i)
            inserted = Array(i..<i + newElements.count)
        }

        arrayDidChange(ArrayChangeEvent(inserted: inserted))
    }

    public mutating func replaceRange<C : CollectionType where C.Generator.Element == Element>(subRange: Range<Int>, with newCollection: C) {

        var inserted: [Int] = []
        var deleted: [Int] = []
        
        dispatch_sync(self.lockUpdateQueue) {
            let oldCount = elements.count
            elements.replaceRange(subRange, with: newCollection)
            
            if let first = subRange.first {
                let newCount = elements.count
                let end = first + (newCount - oldCount) + subRange.count
                inserted = Array(first..<end)
                deleted = Array(subRange)
            }
            else if newCollection.count > 0 && elements.count > 0 && subRange.count == 0 {
                // If replace is an insert send array change event
                inserted = Array(0..<elements.count)
            }
        }
        
        arrayDidChange(ArrayChangeEvent(inserted: inserted,
                                         deleted: deleted))
    }

    public mutating func popLast() -> Element? {
        var e: Element?
        var deleted: [Int] = []

        dispatch_sync(self.lockUpdateQueue) {
            e = elements.popLast()
            deleted = [elements.count]
        }

        if let _ = e {
            arrayDidChange(ArrayChangeEvent(deleted: deleted))
        }

        return e
    }
}

extension ObservableArray: CustomDebugStringConvertible {
    public var description: String {
        return elements.description
    }
}

extension ObservableArray: CustomStringConvertible {
    public var debugDescription: String {
        return elements.debugDescription
    }
}

extension ObservableArray: CollectionType {
    public subscript(index: Int) -> Element {
        get {
            return elements[index]
        }
        set {
            elements[index] = newValue
            if index == elements.count {
                arrayDidChange(ArrayChangeEvent(inserted: [index]))
            } else {
                arrayDidChange(ArrayChangeEvent(updated: [index]))
            }
        }
    }

    public subscript(bounds: Range<Int>) -> ArraySlice<Element> {
        get {
            return elements[bounds]
        }
        set {
            elements[bounds] = newValue
            guard let first = bounds.first else {
                return
            }
            arrayDidChange(ArrayChangeEvent(inserted: Array(first..<first + newValue.count),
                                             deleted: Array(bounds)))
        }
    }
}
