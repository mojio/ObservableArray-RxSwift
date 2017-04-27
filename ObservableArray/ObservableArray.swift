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

    internal let lockUpdateQueue = DispatchQueue(label: "ObservableArrayLockUpdateQueue")
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
        
        self.lockUpdateQueue.sync {
            if elementsSubject == nil {
                self.elementsSubject = BehaviorSubject<[Element]>(value: self.elements)
            }
        }
        
        return elementsSubject
    }

    public mutating func rx_events() -> Observable<EventType> {
        
        self.lockUpdateQueue.sync {
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
    
    public var first: Element? {
        return elements.first
    }
    
    public var last: Element? {
        return elements.last
    }
}

extension ObservableArray: MutableCollection {
    public mutating func reserveCapacity(_ minimumCapacity: Int) {
        self.lockUpdateQueue.sync {
            elements.reserveCapacity(minimumCapacity)
        }
    }

    public mutating func append(_ newElement: Element) {
        var inserted: [Int] = []
        
        self.lockUpdateQueue.sync {
            elements.append(newElement)
            inserted = [elements.count - 1]
        }

        arrayDidChange(ArrayChangeEvent(inserted: inserted))
    }

    public mutating func append<S : Sequence>(contentsOf newElements: S) where S.Iterator.Element == Element {
        var inserted: [Int] = []
        
        self.lockUpdateQueue.sync {
            let end = elements.count
            elements.append(contentsOf: newElements)
            guard end != elements.count else {
                return
            }

            inserted = Array(end..<elements.count)
        }

        guard inserted.count > 0 else { return }
        arrayDidChange(ArrayChangeEvent(inserted: inserted))
    }

    public mutating func appendContentsOf<C : Collection>(_ newElements: C) where C.Iterator.Element == Element {
        guard !newElements.isEmpty else {
            return
        }
        
        var inserted: [Int] = []
        
        self.lockUpdateQueue.sync {
            let end = elements.count
            elements.append(contentsOf: newElements)
            inserted = Array(end..<elements.count)
        }
        
        arrayDidChange(ArrayChangeEvent(inserted: inserted))
    }

    public mutating func removeLast() -> Element {
        var e: Element? = nil
        var deleted: [Int] = []
        
        self.lockUpdateQueue.sync {
            e = elements.removeLast()
            deleted = [elements.count]
        }

        arrayDidChange(ArrayChangeEvent(deleted: deleted))
        
        // Item must exist
        return e! as Element
    }

    public mutating func insert(_ newElement: Element, at i: Int) {
        var inserted: [Int] = []

        self.lockUpdateQueue.sync {
            elements.insert(newElement, at: i)
            inserted = [i]
        }

        arrayDidChange(ArrayChangeEvent(inserted: inserted))
    }

    public mutating func remove(at index: Int) -> Element {
        var e: Element? = nil
        var deleted: [Int] = []

        self.lockUpdateQueue.sync {
            e = elements.remove(at: index)
            deleted = [index]
        }
        
        arrayDidChange(ArrayChangeEvent(deleted: deleted))
        
        // Item must exist
        return e! as Element
    }

    public mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
        guard !elements.isEmpty else {
            return
        }
        
        var deleted: [Int] = []
        
        self.lockUpdateQueue.sync {
            let es = elements
            elements.removeAll(keepingCapacity: keepCapacity)
            deleted = Array(0..<es.count)
        }

        arrayDidChange(ArrayChangeEvent(deleted: deleted))
    }

    public mutating func insert(contentsOf newElements: [Element], at i: Int) {
        guard !newElements.isEmpty else {
            return
        }
        
        var inserted: [Int] = []
        
        self.lockUpdateQueue.sync {
            elements.insert(contentsOf: newElements, at: i)
            inserted = Array(i..<i + newElements.count)
        }

        arrayDidChange(ArrayChangeEvent(inserted: inserted))
    }

    public mutating func popLast() -> Element? {
        var e: Element?
        var deleted: [Int] = []

        self.lockUpdateQueue.sync {
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
        
        self.lockUpdateQueue.sync {
            let oldCount = elements.count
            elements.replaceSubrange(subRange, with: newCollection)
            
            let first = subRange.lowerBound
            let newCount = elements.count
            let end = first + (newCount - oldCount) + subRange.count
            inserted = Array(first..<end)
            deleted = Array(subRange.lowerBound..<subRange.upperBound)
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
            let first = bounds.lowerBound
            arrayDidChange(ArrayChangeEvent(inserted: Array(first..<first + newValue.count),
                                            deleted: Array(bounds.lowerBound..<bounds.upperBound)))
        }
    }
}

// Predicate Methods
extension ObservableArray {
    public mutating func remove(where predicate: (Element) -> Bool)  {
        
        var inserted: [Int] = []
        var deleted: [Int] = []
        
        self.lockUpdateQueue.sync {
            let newCollection = self.filter{includeElement in
                !predicate(includeElement)
            }
            
            // Don't mutate unless there is a change - triggers excessive events
            if newCollection.count == self.count {
                return
            }
            
            let subRange = 0..<self.count
            let oldCount = newCollection.count
 
            elements.replaceSubrange(subRange, with: newCollection)
            
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
    
    public mutating func insert(_ newElement : Element, after predicate : (Element) -> Bool) {
        
        var inserted: [Int] = []
        
        self.lockUpdateQueue.sync {
            if let index = self.index(where: predicate) {
                elements.insert(newElement, at: index + 1)
                inserted = [index + 1]
            }
            else {
                elements.append(newElement)
                inserted = [elements.count - 1]
            }
        }
        
        arrayDidChange(ArrayChangeEvent(inserted: inserted))
    }
    
    public mutating func insert(_ newElement : Element, before predicate : (Element) -> Bool) {
        
        var inserted: [Int] = []
        
        self.lockUpdateQueue.sync {
            if let index = self.index(where: predicate) {
                elements.insert(newElement, at: index)
                inserted = [index]
            }
            else {
                elements.append(newElement)
                inserted = [elements.count - 1]
            }
        }
        
        arrayDidChange(ArrayChangeEvent(inserted: inserted))
    }
    
    public func contains(where predicate: (Element) -> Bool) -> Bool {
        return self.index(where: predicate) != nil
    }
}
