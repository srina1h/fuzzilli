

// A mutator that specifically transforms the provided positive test case

// (repeatedly sorting with a custom comparator) into the negative test case

// (repeatedly sorting a copy of an array using the default sort).

// This targets a specific JavaScript engine optimization pattern related to

// Array.prototype.sort with custom comparators.

public class CircumventSortOptimizationMutator: CustomMutator {



    public init() {

        super.init(name: "CircumventSortOptimizationMutator")

    }



    public override func mutate(_ program: Program, using b: ProgramBuilder, for fuzzer: Fuzzer) -> Bool {

        // Heuristic check: Does the program contain the pattern we want to change?

        // Look for a CallMethod instruction for "sort" that takes more than one argument

        // (implying a custom comparator function is being passed).

        // This is a simplified check sufficient for this specific transformation.

        var foundTargetPattern = false

        for instr in program.code {

            if let call = instr.op as? CallMethod,

               call.methodName == "sort",

               instr.numInputs > 1 // obj + comparator = 2+ inputs

            {

                // Basic check is sufficient for this targeted mutator

                foundTargetPattern = true

                break

            }

        }



        // If the target pattern isn't found, don't apply the mutation.

        guard foundTargetPattern else {

            return false

        }



        // Replace the entire program with the negative test case structure.

        b.reset()



        // Build the FuzzIL code for the negative test case:

        // function circumvent_sort_optimization() {

        let circumventFunc = b.beginFunction(name: "circumvent_sort_optimization", isStrict: false) { _ in

            // var len = 100;

            let len = b.loadInt(100)

            // var templateArr = [];

            let templateArr = b.createArray(with: [])



            // // Initialize with data sortable by the default sort (e.g., strings or numbers)

            // for (var j = 0; j < len; j++) {

            b.loop(header: {

                let j = b.loadInt(0) // Initializer: let j = 0

                return j

            }, condition: { j in // Condition: j < len

                return b.compare(j, with: len, using: .lessThan)

            }, afterthought: { j in // Afterthought: j++

                b.unary(.PostInc, j)

            }) { j in // Loop Body

                // // Use random numbers converted to strings for default lexicographical sort

                // templateArr.push(String(Math.random()));

                let math = b.loadBuiltin("Math")

                let randomVal = b.callMethod("random", on: math)

                let randomStr = b.convertToString(randomVal)

                b.callMethod("push", on: templateArr, withArgs: [randomStr])

            } // End init loop



            // var t = new Date();

            let dateConstructor = b.loadBuiltin("Date")

            let tStart = b.construct(dateConstructor)



            // Define loop count

            let loopCount = b.loadInt(100_000)



            // // Perform the sort operation many times, similar to the original test structure

            // // We need a variable to hold the result of the last sort.

            // // The loop construct in FuzzIL's builder returns the result of the last iteration.

            // for (var i = 0; i < 100_000; i++) {

            // Need to capture the result of the *last* sort call. The loop builder helps here.

            let lastSortedArr = b.loop(header: {

                let i = b.loadInt(0) // Initializer: let i = 0

                // Initialize loop state. The loop needs a placeholder return value for the first iteration,

                // which will be replaced by the actual sorted array in subsequent iterations.

                // We pass the loop counter `i` through the state.

                 let initialResult = b.loadUndefined()

                 return (i, initialResult)

            }, condition: { state in // Condition: i < loopCount

                let (i, _) = state

                return b.compare(i, with: loopCount, using: .lessThan)

            }, afterthought: { state in // Afterthought: i++

                var (i, result) = state

                b.unary(.PostInc, i)

                return (i, result) // Pass the result from the previous iteration body

            }) { state -> Variable in // Loop Body - returns the sorted array

                // let (i, _) = state // Loop counter `i` is available if needed



                // // Create a copy of the array in each iteration

                // var arrToSort = templateArr.slice();

                let arrToSort = b.callMethod("slice", on: templateArr)



                // // Call Array.prototype.sort without providing a custom comparator function.

                // This uses the default sort.

                let currentSortedArr = b.callMethod("sort", on: arrToSort)



                // Return the result of this iteration's sort operation.

                // This value will be passed to the next iteration's afterthought state

                // and will be the final return value of the loop construct after the last iteration.

                return currentSortedArr

            } // End main loop



            // lastSortedArr now holds the result from the final loop iteration.

            guard let finalSortedResult = lastSortedArr else {

                 // Should not happen if the loop runs at least once.

                 // As a fallback, load undefined or handle error.

                 // For simplicity here, we might just let it potentially crash if loopCount is 0,

                 // or assign templateArr if that makes sense. Let's assign undefined.

                 // Realistically, loopCount is 100_000, so it will run.

                 let fallbackResult = b.loadUndefined()

                 b.print(fallbackResult) // Indicate something might be wrong

                 b.doReturn(fallbackResult)

                 return // Exit function early if loop didn't produce result

            }



            // print(new Date() - t);

            let tEnd = b.construct(dateConstructor)

            // Use getTime() for explicit millisecond values for subtraction

            let tEndMillis = b.callMethod("getTime", on: tEnd)

            let tStartMillis = b.callMethod("getTime", on: tStart)

            let duration = b.binary(tEndMillis, tStartMillis, with: .Sub) // end - start

            b.print(duration)



            // // Return the result of the last sort operation, mirroring the original structure

            // return lastSortedArr;

            b.doReturn(finalSortedResult)

        } // End Function Definition



        // // Call the function

        // circumvent_sort_optimization();

        b.callFunction(circumventFunc)



        // The ProgramBuilder `b` now contains the FuzzIL code for the negative test case.

        // The Fuzzilli engine will use this newly built program.

        return true // Mutation was successful

    }

}
