import SwiftUI

/// Test runner for debug component property-based tests
/// Executes Properties 22 and 23 validation
struct RunDebugComponentTests {
    
    /// Executes all debug component property tests
    static func runAllDebugTests() {
        print("🧪 Running Debug Component Property Tests...")
        print("=" * 50)
        
        let results = V2DebugComponentTests.runAllTests()
        
        var allPassed = true
        var totalTests = 0
        var passedTests = 0
        
        for result in results {
            totalTests += 1
            
            print("\n📋 Test: \(result.description)")
            print("   Iterations: \(result.totalIterations)")
            
            if result.isSuccess {
                print("   ✅ PASSED")
                passedTests += 1
            } else {
                print("   ❌ FAILED")
                print("   Failures: \(result.failures.count)/\(result.totalIterations)")
                print("   Success Rate: \(String(format: "%.1f", result.successRate * 100))%")
                
                // Show first few failures for debugging
                for (index, failure) in result.failures.prefix(3).enumerated() {
                    print("   Failure \(index + 1): \(failure.description)")
                    print("   Input: \(failure.input)")
                }
                
                if result.failures.count > 3 {
                    print("   ... and \(result.failures.count - 3) more failures")
                }
                
                allPassed = false
            }
        }
        
        // Additional validation tests
        print("\n🔍 Running Additional Validation Tests...")
        
        let layerComplianceResult = V2DebugComponentTests.validateDebugComponentLayerCompliance()
        print("   Debug Layer Compliance: \(layerComplianceResult ? "✅ PASSED" : "❌ FAILED")")
        if !layerComplianceResult { allPassed = false }
        
        let nonBlockingResult = V2DebugComponentTests.validateDebugOverlayNonBlocking()
        print("   Debug Overlay Non-Blocking: \(nonBlockingResult ? "✅ PASSED" : "❌ FAILED")")
        if !nonBlockingResult { allPassed = false }
        
        // Summary
        print("\n" + "=" * 50)
        print("📊 Debug Component Test Summary:")
        print("   Property Tests: \(passedTests)/\(totalTests) passed")
        print("   Overall Result: \(allPassed ? "✅ ALL TESTS PASSED" : "❌ SOME TESTS FAILED")")
        
        if allPassed {
            print("\n🎉 All debug component properties validated successfully!")
            print("   ✓ Property 22: Interaction Layer Precedence")
            print("   ✓ Property 23: Overlay Layer Positioning")
        } else {
            print("\n⚠️  Some debug component tests failed. Review the failures above.")
        }
        
        print("=" * 50)
    }
    
    /// Runs a specific property test by name
    static func runSpecificTest(_ testName: String) {
        print("🧪 Running Specific Debug Test: \(testName)")
        print("=" * 40)
        
        let result: V2PropertyTestResult
        
        switch testName.lowercased() {
        case "interaction", "precedence", "property22":
            result = V2DebugComponentTests.testInteractionLayerPrecedence()
        case "overlay", "positioning", "property23":
            result = V2DebugComponentTests.testOverlayLayerPositioning()
        default:
            print("❌ Unknown test name: \(testName)")
            print("Available tests: interaction, overlay")
            return
        }
        
        print("\n📋 Test: \(result.description)")
        print("   Iterations: \(result.totalIterations)")
        
        if result.isSuccess {
            print("   ✅ PASSED")
        } else {
            print("   ❌ FAILED")
            print("   Failures: \(result.failures.count)/\(result.totalIterations)")
            print("   Success Rate: \(String(format: "%.1f", result.successRate * 100))%")
            
            for (index, failure) in result.failures.enumerated() {
                print("   Failure \(index + 1): \(failure.description)")
                print("   Input: \(failure.input)")
            }
        }
        
        print("=" * 40)
    }
}

// MARK: - String Extension for Formatting

extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}

// MARK: - Debug Test Execution Entry Point

/// Entry point for running debug component tests
/// Can be called from other test runners or standalone
@MainActor
struct V2DebugTestExecutor {
    
    /// Executes debug component tests and returns results
    static func execute() -> V2DebugTestResults {
        let startTime = Date()
        
        let propertyResults = V2DebugComponentTests.runAllTests()
        let layerCompliance = V2DebugComponentTests.validateDebugComponentLayerCompliance()
        let nonBlocking = V2DebugComponentTests.validateDebugOverlayNonBlocking()
        
        let endTime = Date()
        let executionTime = endTime.timeIntervalSince(startTime)
        
        return V2DebugTestResults(
            propertyResults: propertyResults,
            layerCompliance: layerCompliance,
            nonBlocking: nonBlocking,
            executionTime: executionTime
        )
    }
}

/// Results container for debug component tests
struct V2DebugTestResults {
    let propertyResults: [V2PropertyTestResult]
    let layerCompliance: Bool
    let nonBlocking: Bool
    let executionTime: TimeInterval
    
    var allPassed: Bool {
        return propertyResults.allSatisfy(\.isSuccess) && layerCompliance && nonBlocking
    }
    
    var totalTests: Int {
        return propertyResults.count + 2 // +2 for additional validation tests
    }
    
    var passedTests: Int {
        let propertyPassed = propertyResults.filter(\.isSuccess).count
        let additionalPassed = (layerCompliance ? 1 : 0) + (nonBlocking ? 1 : 0)
        return propertyPassed + additionalPassed
    }
}