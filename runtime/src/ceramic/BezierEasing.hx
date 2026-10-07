package ceramic;

import ceramic.Assert.*;

using ceramic.Extensions;

/**
 * High-performance Bezier curve easing for smooth animations.
 * 
 * This class implements cubic and quadratic Bezier easing functions with a
 * closed-form solver and intelligent caching. Based on the implementation from
 * https://github.com/gre/bezier-easing, extended to support both cubic and
 * quadratic curves.
 * 
 * ## Features
 * 
 * - **Cubic Bezier**: Standard CSS-style cubic-bezier(x1, y1, x2, y2)
 * - **Quadratic Bezier**: Simplified two-point control
 * - **Exact and fast**: Closed-form solver, no iteration
 * - **Instance Caching**: Automatic reuse of common easing functions
 * - **Linear Detection**: Automatically optimizes linear easings
 * 
 * ## Usage Examples
 * 
 * ```haxe
 * // Create cubic bezier (CSS-style)
 * var easeInOut = new BezierEasing(0.42, 0, 0.58, 1);
 * var progress = easeInOut.ease(0.5); // Returns ~0.5
 * 
 * // Create quadratic bezier (single control point)
 * var easeQuad = new BezierEasing(0.5, 0.8);
 * 
 * // Use cached instances for better performance
 * var cached = BezierEasing.get(0.25, 0.1, 0.25, 1); // ease-out
 * 
 * // Common easing curves
 * var easeIn = BezierEasing.get(0.42, 0, 1, 1);
 * var easeOut = BezierEasing.get(0, 0, 0.58, 1);
 * var easeInOut = BezierEasing.get(0.42, 0, 0.58, 1);
 * ```
 * 
 * ## Performance Notes
 * 
 * - Each call solves the cubic in closed form (no sample table, no iteration)
 * - Linear easings bypass all calculations
 * - Cache stores up to 10,000 instances
 * 
 * @see ceramic.Easing For pre-defined easing functions
 * @see ceramic.Tween For animation implementation
 */
class BezierEasing {

    /** Constant for quadratic to cubic conversion */
    static var TWO_THIRD = 2.0 / 3.0;

    /** Maximum number of cached instances before clearing cache */
    static var CACHE_SIZE:Int = 10000;

    /** Whether this easing is linear (optimization flag) */
    var linearEasing = false;

    /** Coefficients of x(t) = ((2a * t + 3b) * t + 3c) * t */
    var a:Float;
    var b:Float;
    var c:Float;

    /** Coefficients of y(t) = ((ay * t + by) * t + cy) * t */
    var ay:Float;
    var by:Float;
    var cy:Float;

    /** Whether this instance is stored in the cache */
    var cached:Bool = false;

    /** Whether this is a quadratic (vs cubic) curve */
    var quadratic:Bool = false;

    /** Original quadratic X1 value (before conversion) */
    var mQuadraticX1:Float;

    /** Original quadratic X2 value (before conversion) */
    var mQuadraticX2:Float;

    /** First control point X coordinate (0-1) */
    var mX1:Float;

    /** First control point Y coordinate */
    var mY1:Float;

    /** Second control point X coordinate (0-1) */
    var mX2:Float;

    /** Second control point Y coordinate */
    var mY2:Float;

    /**
     * Create a new instance with the given arguments.
     * If only `x1` and `y1` are provided, the curve is treated as quadratic.
     * If all four values `x1`, `y1`, `x2`, `y2` are provided,
     * the curve is treated as cubic.
     */
    public function new(x1:Float, y1:Float, ?x2:Float, ?y2:Float) {

        inline configure(x1, y1, x2, y2);

    }

    /**
     * Configure the instance with the given arguments.
     * If only `x1` and `y1` are provided, the curve is treated as quadratic.
     * If all four values `x1`, `y1`, `x2`, `y2` are provided,
     * the curve is treated as cubic.
     */
    public function configure(x1:Float, y1:Float, ?x2:Float, ?y2:Float) {

        // If this instance was part of the cache,
        // it should be removed as its settings will change
        if (cached)
            removeFromCache(mX1, mY1, mX2, mY2);

        if (x2 == null || y2 == null) {
            this.quadratic = true;
            this.mQuadraticX1 = x1;
            this.mQuadraticX2 = x2;
            this.mX1 = quadraticToCubicCP1(x1);
            this.mY1 = quadraticToCubicCP1(y1);
            this.mX2 = quadraticToCubicCP2(x1);
            this.mY2 = quadraticToCubicCP2(y1);
        }
        else {
            this.quadratic = false;
            this.mX1 = x1;
            this.mY1 = y1;
            this.mX2 = x2;
            this.mY2 = y2;
        }

        assert((0 <= mX1 && mX1 <= 1 && 0 <= mX2 && mX2 <= 1), 'bezier x values must be in [0, 1] range');

        if (mX1 == mY1 && mX2 == mY2) {
            linearEasing = true;
        }
        else {
            linearEasing = false;
            a = (3 * mX1 - 3 * mX2 + 1) / 2;
            b = mX2 - 2 * mX1;
            c = mX1;
            ay = 3 * mY1 - 3 * mY2 + 1;
            by = 3 * (mY2 - 2 * mY1);
            cy = 3 * mY1;
        }

    }

    /**
     * Calculates the eased value for the given progress.
     * 
     * @param x Progress value from 0 to 1
     * @return Eased value (typically 0 to 1, but can overshoot)
     * 
     * ```haxe
     * var easing = new BezierEasing(0.42, 0, 0.58, 1);
     * tween.progress = easing.ease(elapsed / duration);
     * ```
     */
    public function ease(x:Float):Float {

        if (linearEasing) return x;
        // x outside (0, 1) saturates to 0 / 1
        if (x <= 0) return 0;
        if (x >= 1) return 1;
        if (Math.isNaN(x)) return x;
        var t = solveTForX(x);
        return ((ay * t + by) * t + cy) * t;

    }

    /**
     * Solves x(t) = ((2a * t + 3b) * t + 3c) * t = x for t, with x in (0, 1):
     * u = 1/t is the largest real root of x·u³ − 3c·u² − 3b·u − 2a = 0
     */
    function solveTForX(x:Float):Float {

        var j = 1 / Math.max(c, Math.sqrt(x));
        var k = x * j;
        var l = k * j;
        var s = c * j;
        var q = b * l;
        var m = s * s + q;
        var h = -s * (s * s + 1.5 * q) - a * k * l;
        var d = h * h - m * m * m;
        var v:Float;
        if (m == 0 || d > 1e-12 * h * h) {
            // one real root (Cardano)
            var w = h < 0 ? h - Math.sqrt(d) : h + Math.sqrt(d);
            var u = w < 0 ? Math.pow(-w, 1 / 3) : -Math.pow(w, 1 / 3);
            v = u + m / u;
            if (Math.isNaN(v)) v = 0; // triple root (m = h = 0)
        } else {
            // three real roots, take the largest
            var r = Math.sqrt(m);
            v = 2 * r * Math.cos(Math.acos(Math.max(-1, Math.min(1, -h / (m * r)))) / 3);
        }
        return Math.min(1, k / (v + s));

    }

    /**
     * Converts a quadratic control point to the first cubic control point.
     */
    inline static function quadraticToCubicCP1(p:Float):Float {

        return TWO_THIRD * p;

    }

    /**
     * Converts a quadratic control point to the second cubic control point.
     */
    inline static function quadraticToCubicCP2(p:Float):Float {

        return 1.0 + TWO_THIRD * (p - 1.0);

    }

    /// Cache

    /** Map of cached instances by parameter hash */
    static var cachedInstances:IntMap<Array<BezierEasing>> = null;

    /** Current number of cached instances */
    static var numCachedInstances:Int = 0;

    /**
     * Removes this instance from the cache when its parameters change.
     */
    function removeFromCache(x1:Float, y1:Float, x2:Float, y2:Float):Void {

        cached = false;

        var key = cacheKey(x1, y1, x2, y2);
        if (cachedInstances != null) {
            var list = cachedInstances.getInline(key);
            if (list != null) {
                if (list.length == 1 && list.unsafeGet(0) == this) {
                    cachedInstances.remove(key);
                }
                else {
                    list.remove(this);
                }
            }
        }

    }

    /**
     * Generates a hash key for caching based on control points.
     * Note: This is a simple hash that may have collisions.
     */
    inline static function cacheKey(x1:Float, y1:Float, x2:Float, y2:Float):Int {

        var floatKey = x1 * 10000 + y1 * 100000 + x2 * 1000000 + y2 * 10000000;
        return Std.int(floatKey);

    }

    /**
     * Clears all cached BezierEasing instances.
     * 
     * Call this if you need to free memory or have created
     * many temporary easing functions.
     */
    public static function clearCache():Void {

        cachedInstances = null;
        numCachedInstances = 0;

    }

    /**
     * Get or create a `BezierEasing` instance with the given parameters.
     * Created instances are cached and reused.
     */
    public static function get(x1:Float, y1:Float, ?x2:Float, ?y2:Float):BezierEasing {

        var quadratic = (x2 == null || y2 == null);

        var _x1:Float = quadratic ? quadraticToCubicCP1(x1) : x1;
        var _y1:Float = quadratic ? quadraticToCubicCP1(y1) : y1;
        var _x2:Float = quadratic ? quadraticToCubicCP2(x1) : x2;
        var _y2:Float = quadratic ? quadraticToCubicCP2(y1) : y2;

        var result:BezierEasing = null;

        var key = cacheKey(_x1, _y1, _x2, _y2);
        if (cachedInstances == null) {
            cachedInstances = new IntMap<Array<BezierEasing>>();
        }
        var list = cachedInstances.getInline(key);
        if (list == null) {
            if (numCachedInstances >= CACHE_SIZE) {
                clearCache();
            }
            // No list matching key, create new list with new instance
            result = new BezierEasing(_x1, _y1, _x2, _y2);
            cachedInstances.set(key, [result]);
            numCachedInstances++;
        }
        else {
            // Look for an existing instance, starting from the latest added
            var i = list.length - 1;
            while (i >= 0) {
                var instance = list.unsafeGet(i);
                if (instance.mX1 == _x1 && instance.mY1 == _y1
                && instance.mX2 == _x2 && instance.mY2 == _y2) {
                    // Found it! reuse instance
                    result = instance;
                    break;
                }
                i--;
            }
            if (result == null) {
                // Nothing found, create a new instance
                result = new BezierEasing(x1, y1, x2, y2);
                result.cached = true;
                list.push(result);
            }
        }

        return result;

    }

}
