import Foundation
import Testing
@testable import HammerCore

@Suite struct CalculatorTests {
    func value(_ s: String) -> Double? { Calculator.evaluate(s) }

    @Test func ownerExamples() {
        #expect(value("8/32") == 0.25)
        #expect(value("10 % 3") == 1)
        #expect(value("8(5+3*2+(4*2 + 5 - 10)/2)") == 100)
    }

    @Test func precedenceAndAssociativity() {
        #expect(value("2+3*4") == 14)
        #expect(value("10-4-3") == 3)
        #expect(value("64/4/2") == 8)
        #expect(value("2^3^2") == 512)
        #expect(value("-2^2") == -4)
        #expect(value("2*-3") == -6)
        #expect(value("7 % 4 * 2") == 6)
    }

    @Test func implicitMultiplication() {
        #expect(value("(1+2)(3+4)") == 21)
        #expect(value("2(3)") == 6)
        #expect(value("(2)3") == 6)
        #expect(value("2pi") == 2 * Double.pi)
        #expect(value("3 sqrt(4)") == 6)
    }

    @Test func percentAndModulo() {
        #expect(value("50%") == 0.5)
        #expect(value("200*10%") == 20)
        #expect(value("10% + 1") == 1.1)
        #expect(value("-7 % 3") == -1)
        #expect(value("7.5 % 2") == 1.5)
    }

    @Test func functionsConstantsAndSymbols() {
        #expect(value("sqrt(16)+1") == 5)
        #expect(value("√9") == 3)
        #expect(value("√(3+6)") == 3)
        #expect(value("PI") == Double.pi)
        #expect(value("π*2") == 2 * Double.pi)
        #expect(value("e^1") == M_E)
        #expect(value("6×7") == 42)
        #expect(value("9÷3") == 3)
        #expect(value(".5+.5") == 1)
    }

    @Test func unclosedParenthesesCloseAtTheEnd() {
        #expect(value("2*(3+4") == 14)
        #expect(value("((1+1") == 2)
    }

    @Test func rejectsNonMathAndInvalidInput() {
        for s in ["", "  ", "safari", "1Password", "8+", "*2", "2..3", "1/0", "5 % 0", "sqrt(-1)", "()", "2)", "foo(2)", "1,000+1", "pi pi pi("] {
            #expect(value(s) == nil, "\(s)")
        }
    }

    @Test func plainNumbersAreNotCalculations() {
        for s in ["42", "-5", "+3", "3.14", "pi", "(5)"] {
            #expect(Calculator.result(for: s) == nil, "\(s)")
        }
    }

    @Test func formatsReadably() {
        #expect(Calculator.format(0.1 + 0.2) == "0.3")
        #expect(Calculator.format(1.0 / 3) == "0.333333333333")
        #expect(Calculator.format(1234567) == "1234567")
        #expect(Calculator.format(-0.0) == "0")
        #expect(Calculator.format(-2.5) == "-2.5")
        #expect(Calculator.format(1e20) == "1e+20")
        #expect(Calculator.format(0.00001234) == "1.234e-05")
    }

    @Test func resultRowCopiesTheValue() throws {
        let r = try #require(Calculator.result(for: "8/32"))
        #expect(r.title == "0.25")
        #expect(r.section == Calculator.section)
        #expect(r.action == .copyText("0.25"))
    }
}
