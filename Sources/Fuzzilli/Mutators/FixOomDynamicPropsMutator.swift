import Foundation



/// A mutator that specifically targets a known crashing pattern involving

/// dynamic property assignment inside an oomTest within an evaluate call,

/// and replaces it with a non-crashing version using pre-defined properties.

///

/// It transforms code similar to:

/// ```javascript

/// b = function() {}

/// evaluate(`

///   oomTest(function() {

///     var c = new b

///     for (d in this)

///       c[d] = []

///   });

/// `);

/// ```

/// Into code functionally similar to:

/// ```javascript

/// evaluate(`

///   function MyConstructor() {

///       this.prop1 = null;

///       this.prop2 = null;

///       // ... potentially more properties

///   }

///   oomTest(function() {

///       var c = new MyConstructor();

///       c.prop1 = [1];

///       c.prop2 = [2];

///       // ... assignments to pre-defined properties

///   });

/// `);

/// ```

/// By replacing the `LoadString` instruction containing the problematic code.

public class FixOomDynamicPropsMutator: BaseInstructionMutator {



    // The pattern fragments to identify the problematic string content.

    // Using fragments makes the check slightly more robust to whitespace variations.

    let patternFrag1 = "oomTest(function() {"

    let patternFrag2 = "new b" // Assuming 'b' is the constructor name from the positive case

    let patternFrag3 = "for (d in this)"

    let patternFrag4 = "[d] = []" // Check for assignment within the loop



    // The replacement JavaScript code string.

    let replacementCode = """

      function MyConstructor() {

          // Pre-define some properties to avoid dynamic addition inside oomTest

          this.prop1 = null;

          this.prop2 = null;

          this.prop3 = null;

          this.prop4 = null;

      }

      oomTest(function() {

          // Create an object with a fixed initial shape

          var c = new MyConstructor();

          // Assign values to existing properties instead of dynamically adding them.

          // This avoids iterating over 'this' and avoids dynamic slot allocation

          // during the oomTest loop which triggered the assertion.

          c.prop1 = [1];

          c.prop2 = [2];

          c.prop3 = [3];

          c.prop4 = [4];

      });

    """



    public init() {

        // This is a very specific transformation, likely run only once.

        super.init(name: "FixOomDynamicPropsMutator", maxSimultaneousMutations: 1)

    }



    public override func canMutate(_ instr: Instruction) -> Bool {

        // We target the LoadString instruction.

        guard let op = instr.op as? LoadString else {

            return false

        }



        // Check if the string contains all the fragments of the problematic pattern.

        // Normalization helps, but checking for fragments is often sufficient and simpler.

        let currentString = op.value

        return currentString.contains(patternFrag1) &&

               currentString.contains(patternFrag2) &&

               currentString.contains(patternFrag3) &&

               currentString.contains(patternFrag4)

    }



    public override func mutate(_ instr: Instruction, _ b: ProgramBuilder) {

        guard instr.op is LoadString else {

            // Should not happen due to canMutate check, but good practice.

            b.adopt(instr)

            return

        }



        // Replace the LoadString instruction with a new one containing the fixed code.

        // The ProgramBuilder handles replacing the output variable correctly.

        b.loadString(replacementCode)

        b.trace("Applied FixOomDynamicPropsMutator")



        // Note: This mutator only replaces the string content used in `evaluate`.

        // It does not explicitly remove the preceding `b = function() {}` code block

        // from the positive test case. That code might become dead code in the

        // mutated program, potentially removed by Fuzzilli's minimizer later.

        // This achieves the core goal of fixing the crash within the evaluated code.

    }

}
