﻿/**
 * ae.utils.range
 *
 * License:
 *   This Source Code Form is subject to the terms of
 *   the Mozilla Public License, v. 2.0. If a copy of
 *   the MPL was not distributed with this file, You
 *   can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * Authors:
 *   Vladimir Panteleev <vladimir@thecybershadow.net>
 */

module ae.utils.range;

import std.range.primitives;

import ae.utils.meta : isDebug;

/// An equivalent of an array range, but which maintains
/// a start and end pointer instead of a start pointer
/// and length. This allows .popFront to be faster.
/// Optionally, omits bounds checking for even more speed.
// TODO: Can we make CHECKED implicit, controlled by
//       -release, like regular arrays?
// TODO: Does this actually make a difference in practice?
//       Run some benchmarks...
struct FastArrayRange(T, bool CHECKED=isDebug)
{
	T* ptr, end;

	this(T[] arr)
	{
		ptr = arr.ptr;
		end = ptr + arr.length;
	}

	@property T front()
	{
		static if (CHECKED)
			assert(!empty);
		return *ptr;
	}

	void popFront()
	{
		static if (CHECKED)
			assert(!empty);
		ptr++;
	}

	@property bool empty() { return ptr==end; }

	@property ref typeof(this) save() { return this; }

	T opIndex(size_t index)
	{
		static if (CHECKED)
			assert(index < end-ptr);
		return ptr[index];
	}

	T[] opSlice()
	{
		return ptrSlice(ptr, end);
	}

	T[] opSlice(size_t from, size_t to)
	{
		static if (CHECKED)
			assert(from <= to && to <= end-ptr);
		return ptr[from..to];
	}
}

auto fastArrayRange(T)(T[] arr) { return FastArrayRange!T(arr); }

T[] ptrSlice(T)(T* a, T* b)
{
	return a[0..b-a];
}

unittest
{
	FastArrayRange!ubyte r;
	auto x = r.save;
}

// ************************************************************************

/// Presents a null-terminated pointer (C-like string) as a range.
struct NullTerminated(E)
{
	E* ptr;
	bool empty() { return !*ptr; }
	ref E front() { return *ptr; }
	void popFront() { ptr++; }
	auto save() { return this; }
}
auto nullTerminated(E)(E* ptr)
{
	return NullTerminated!E(ptr);
}

unittest
{
	void test(S)(S s)
	{
		import std.utf, std.algorithm.comparison;
		assert(equal(s.byCodeUnit, s.ptr.nullTerminated));
	}
	// String literals are null-terminated
	test("foo");
	test("foo"w);
	test("foo"d);
}

// ************************************************************************

/// Apply a predicate over each consecutive pair.
template pairwise(alias pred)
{
	import std.range : zip, dropOne;
	import std.algorithm.iteration : map;
	import std.functional : binaryFun;

	auto pairwise(R)(R r)
	{
		return zip(r, r.dropOne).map!(pair => binaryFun!pred(pair[0], pair[1]));
	}
}

///
unittest
{
	import std.algorithm.comparison : equal;
	assert(equal(pairwise!"a+b"([1, 2, 3]), [3, 5]));
	assert(equal(pairwise!"b-a"([1, 2, 3]), [1, 1]));
}

// ************************************************************************

struct InfiniteIota(T)
{
	T front;
	enum empty = false;
	void popFront() { front++; }
	T opIndex(T offset) { return front + offset; }
	InfiniteIota save() { return this; }
}
InfiniteIota!T infiniteIota(T)() { return InfiniteIota!T.init; }

// ************************************************************************

/// Empty range of type E.
struct EmptyRange(E)
{
	@property E front() { assert(false); }
	void popFront() { assert(false); }
	@property E back() { assert(false); }
	void popBack() { assert(false); }
	E opIndex(size_t) { assert(false); }
	enum empty = true;
	enum save = typeof(this).init;
	enum size_t length = 0;
}

/// ditto
EmptyRange!E emptyRange(E)() { return EmptyRange!E.init; }

static assert(isInputRange!(EmptyRange!uint));
static assert(isForwardRange!(EmptyRange!uint));
static assert(isBidirectionalRange!(EmptyRange!uint));
static assert(isRandomAccessRange!(EmptyRange!uint));

// ************************************************************************

/// Like `only`, but evaluates the argument lazily, i.e. when the
/// range's "front" is evaluated.
/// DO NOT USE before this bug is fixed:
/// https://issues.dlang.org/show_bug.cgi?id=11044
auto onlyLazy(E)(lazy E value)
{
	struct Lazy
	{
		bool empty = false;
		@property E front() { assert(!empty); return value; }
		void popFront() { assert(!empty); empty = true; }
		alias back = front;
		alias popBack = popFront;
		@property size_t length() { return empty ? 0 : 1; }
		E opIndex(size_t i) { assert(!empty); assert(i == 0); return value; }
		@property typeof(this) save() { return this; }
	}
	return Lazy();
}

static assert(isInputRange!(typeof(onlyLazy(1))));
static assert(isForwardRange!(typeof(onlyLazy(1))));
static assert(isBidirectionalRange!(typeof(onlyLazy(1))));
static assert(isRandomAccessRange!(typeof(onlyLazy(1))));

unittest
{
	import std.algorithm.comparison;
	import std.range;

	int i;
	auto r = onlyLazy(i);
	i = 1; assert(equal(r, 1.only));
	i = 2; assert(equal(r, 2.only));
}

// ************************************************************************

/// Defer range construction until first empty/front call.
auto lazyInitRange(R)(R delegate() constructor)
{
	bool initialized;
	R r = void;

	ref R getRange()
	{
		if (!initialized)
		{
			r = constructor();
			initialized = true;
		}
		return r;
	}

	struct LazyRange
	{
		bool empty() { return getRange().empty; }
		auto ref front() { return getRange().front; }
		void popFront() { return getRange().popFront; }
	}
	return LazyRange();
}

///
unittest
{
	import std.algorithm.iteration;
	import std.range;

	int[] todo, done;
	chain(
		only({ todo = [1, 2, 3]; }),
		// eager will fail: todo.map!(n => { done ~= n; }),
		lazyInitRange(() => todo.map!(n => { done ~= n; })),
	).each!(dg => dg());
	assert(done == [1, 2, 3]);
}
