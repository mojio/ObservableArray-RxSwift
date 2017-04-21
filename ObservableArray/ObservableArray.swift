//
//  ObservableArray.swift
//  ObservableArray
//
//  Created by Safx Developer on 2015/02/19.
//  Copyright (c) 2016 Safx Developers. All rights reserved.
//

import Foundation
import RxSwift

public struct ArrayChangeEvent {
    public let insertedIndices: [Int]
    public let deletedIndices: [Int]
    public let updatedIndices: [Int]

    fileprivate init(inserted: [Int] = [], deleted: [Int] = [], updated: [Int] = []) {
        assert(inserted.count + deleted.count + updated.count > 0)
        self.insertedIndices = inserted
        self.deletedIndices = deleted
        self.updatedIndices = updated
    }
}

public struct ObservableArray<Element>: ExpressibleByArrayLiteral {
    public typealias EventType = ArrayChangeEvent

    internal let lockUpdateQueue = dispatch_queue_create(nil, DISPATCH_QUEUE_SERIAL)
    internal var eventSubject: PublishSubject<EventType>!
    internal var elementsSubject: BehaviorSubject<[Element]>!
    internal var elements: [Element]

    public init() {
        self.elements = []
    }

    public init(count:Int, repeatedValue: Element) {
        self.elements = Array(repeating: repeatedValue, count: count)
    }

    public init<S : Sequence>(_ s: S) where S.Iterator.Element == Element {
        self.elements = Array(s)
    }

    public init(arrayLiteral elements: Element...) {
        self.elements = elements
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

    fileprivate func arrayDidChange(_ event: EventType) {
        elementsSubject?.onNext(elements)
        eventSubject?.onNext(event)
    }
}

extension ObservableArray: Collection {
    public var capacity: Int {
        return elements.capacity
    }

    /*public var count: Int {
        return elements.count
    }*/

    public var startIndex: Int {
        return elements.startIndex
    }

    public var endIndex: Int {
        return elements.endIndex
    }

    public func index(after i: Int) -> Int {
        return elements.index(after: i)
    }
}

extension ObservableArray: MutableCollection {
    public mutating func reserveCapacity(_ minimumCapacity: Int) {
        dispatch_sync(self.lockUpdateQueue) {
            elements.reserveCapacity(minimumCapacity)
        }
    }

    public mutating func append(_ newElement: Element) {
        var inserted: [Int] = []
        
        dispatch_sync(self.lockUpdateQueue) {
            elements.append(newElement)
            inserted = [elements.count - 1]
        }

        arrayDidChange(ArrayChangeEvent(inserted: inserted))
    }

    public mutating func append<S : Sequence>(contentsOf newElements: S) where S.Iterator.Element == Element {
        var inserted: [Int] = []
        
        dispatch_sync(self.lockUpdateQueue) {
            let end = elements.count
            elements.append(contentsOf: newElements)
            guard end != elements.count else {
                return
            }

            inserted = Array(end..<elements.count)
        }

        arrayDidChange(ArrayChangeEvent(inserted: inserted))
    }

    public mutating func appendContentsOf<C : Collection>(_ newElements: C) where C.Iterator.Element == Element {
        guard !newElements.isEmpty else {
            return
        }
        
        var inserted: [Int] = []
        
        dispatch_sync(self.lockUpdateQueue) {
            let end = elements.count
            elements.append(contentsOf: newElements)
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

    public mutating func insert(_ newElement: Element, at i: Int) {
        var inserted: [Int] = []

        dispatch_sync(self.lockUpdateQueue) {
            elements.insert(newElement, at: i)
            inserted = [i]
        }

        arrayDidChange(ArrayChangeEvent(inserted: inserted))
    }

    public mutating func remove(at index: Int) -> Element {
        var e: Element? = nil
        var deleted: [Int] = []

        dispatch_sync(self.lockUpdateQueue) {
            e = elements.remove(at: index)
            deleted = [index]
        }
        
        arrayDidChange(ArrayChangeEvent(deleted: deleted))
        
        // Item must exist
        return e! as Element
    }

    public mutating func removeAll(_ keepCapacity: Bool = false) {
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

    public mutating func insert(contentsOf newElements: [Element], at i: Int) {
        guard !newElements.isEmpty else {
            return
        }
        
        var inserted: [Int] = []
        
        dispatch_sync(self.lockUpdateQueue) {
            elements.insert(contentsOf: newElements, at: i)
            inserted = Array(i..<i + newElements.count)
        }

        arrayDidChange(ArrayChangeEvent(inserted: inserted))
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

extension ObservableArray: RangeReplaceableCollection {
    public mutating func replaceSubrange<C : Collection>(_ subRange: Range<Int>, with newCollection: C) where C.Iterator.Element == Element {
        var inserted: [Int] = []
        var deleted: [Int] = []
        
        dispatch_sync(self.lockUpdateQueue) {
            let oldCount = elements.count
            elements.replaceSubrange(subRange, with: newCollection)
            
            if let first = subRange.lowerBound {
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
        
        if inserted.count > 0 || deleted.count > 0 {
            arrayDidChange(ArrayChangeEvent(inserted: inserted, deleted: deleted))
        }
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

extension ObservableArray: Sequence {

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
            guard let first = bounds.lowerBound else {
                return
            }
            arrayDidChange(ArrayChangeEvent(inserted: Array(first..<first + newValue.count),
                                            deleted: Array(bounds.lowerBound..<bounds.upperBound)))
        }
    }
}

// Predicate Methods
extension ObservableArray {
    public mutating func remove(predicate: (Element) -> Bool)  {
        
        var inserted: [Int] = []
        var deleted: [Int] = []
        
        dispatch_sync(self.lockUpdateQueue) {
            let newCollection = self.filter{includeElement in
                !predicate(includeElement)
            }
            
            // Don't mutate unless there is a change - triggers excessive events
            if newCollection.count == self.count {
                return
            }
            
            let subRange = 0..<self.count
            let oldCount = newCollection.count
 
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
        
        if inserted.count > 0 || deleted.count > 0 {
            arrayDidChange(ArrayChangeEvent(inserted: inserted, deleted: deleted))
        }
    }
    
    public mutating func insertAfter(newElement : Element, predicate : (Element) -> Bool) {
        
        var inserted: [Int] = []
        
        dispatch_sync(self.lockUpdateQueue) {
            if let index = self.indexOf(predicate) {
                elements.insert(newElement, atIndex: index + 1)
                inserted = [index + 1]
            }
            else {
                elements.append(newElement)
                inserted = [elements.count - 1]
            }
        }
        
        arrayDidChange(ArrayChangeEvent(inserted: inserted))
    }
    
    public mutating func insertBefore(newElement : Element, predicate : (Element) -> Bool) {
        
        var inserted: [Int] = []
        
        dispatch_sync(self.lockUpdateQueue) {
            if let index = self.indexOf(predicate) {
                elements.insert(newElement, atIndex: index)
                inserted = [index]
            }
            else {
                elements.append(newElement)
                inserted = [elements.count - 1]
            }
        }
        
        arrayDidChange(ArrayChangeEvent(inserted: inserted))
    }
    
    public func contains(predicate: (Element) -> Bool) -> Bool {
        return self.indexOf(predicate) != nil
    }
}
