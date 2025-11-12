import pytest
import tempfile
import os
import sys
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent.parent))

from tools.FoG_tools import edit_template_by_diff

class TestEditTemplateByDiff:
    """Test suite for edit_template_by_diff function"""
    
    @pytest.fixture
    def temp_swift_file(self):
        """Create a temporary Swift file for testing"""
        content = """// Line 1: Header
struct Template {
    var name: String
    var value: Int
    
    func oldMethod() {
        print("old")
    }
    
    func anotherMethod() {
        return 42
    }
}
// Line 13: End"""
        
        with tempfile.TemporaryDirectory() as tmpdir:
            codegen_dir = os.path.join(tmpdir, "CodeGen")
            os.makedirs(codegen_dir)
            filepath = os.path.join(codegen_dir, "ProgramTemplates.swift")
            
            with open(filepath, 'w') as f:
                f.write(content)
            
            with patch('tools.FoG_tools.SWIFT_PATH', tmpdir):
                yield filepath
    
    def read_file(self, filepath):
        """Helper to read file contents"""
        with open(filepath, 'r') as f:
            return f.read()
    
    # Test 1: Single line replacement
    def test_single_line_replacement(self, temp_swift_file):
        """Test replacing a single line of code"""
        result = edit_template_by_diff(
            old_text="    var name: String",
            new_text="    var name: String = \"default\"",
            start_line=3,
            end_line=3
        )
        
        assert "OK: Successfully updated" in result
        content = self.read_file(temp_swift_file)
        assert 'var name: String = "default"' in content
        assert content.count('var name') == 1  # Only one occurrence
    
    # Test 2: Multi-line replacement (same number of lines)
    def test_multi_line_replacement_same_count(self, temp_swift_file):
        """Test replacing multiple lines with same number of lines"""
        result = edit_template_by_diff(
            old_text="""    func oldMethod() {
        print("old")
    }""",
            new_text="""    func newMethod() {
        print("new")
    }""",
            start_line=6,
            end_line=8
        )
        
        assert "OK: Successfully updated" in result
        content = self.read_file(temp_swift_file)
        assert "func newMethod()" in content
        assert "oldMethod" not in content
        assert 'print("new")' in content
    
    # Test 3: Multi-line replacement (expanding lines)
    def test_multi_line_replacement_expanding(self, temp_swift_file):
        """Test replacing code that expands to more lines"""
        result = edit_template_by_diff(
            old_text="""    func anotherMethod() {
        return 42
    }""",
            new_text="""    func anotherMethod() {
        let result = calculate()
        print("Result: \\(result)")
        return result
    }
    
    private func calculate() -> Int {
        return 42
    }""",
            start_line=10,
            end_line=12
        )
        
        assert "OK: Successfully updated" in result
        content = self.read_file(temp_swift_file)
        assert "let result = calculate()" in content
        assert "private func calculate()" in content
        lines = content.splitlines()
        assert len(lines) > 13  # Should have more lines now
    
    # Test 4: Multi-line replacement (shrinking lines)
    def test_multi_line_replacement_shrinking(self, temp_swift_file):
        """Test replacing code that shrinks to fewer lines"""
        result = edit_template_by_diff(
            old_text="""    func oldMethod() {
        print("old")
    }
    
    func anotherMethod() {
        return 42
    }""",
            new_text="""    func combinedMethod() -> Int { return 42 }""",
            start_line=6,
            end_line=12
        )
        
        assert "OK: Successfully updated" in result
        content = self.read_file(temp_swift_file)
        assert "func combinedMethod()" in content
        assert "oldMethod" not in content
        assert "anotherMethod" not in content
        lines = content.splitlines()
        assert len(lines) < 13  # Should have fewer lines now
    
    # Test 5: Deletion (empty new_text)
    def test_deletion(self, temp_swift_file):
        """Test deleting lines by using empty new_text"""
        result = edit_template_by_diff(
            old_text="""    
    func anotherMethod() {
        return 42
    }""",
            new_text="",
            start_line=9,
            end_line=12
        )
        
        assert "OK: Successfully updated" in result
        content = self.read_file(temp_swift_file)
        assert "anotherMethod" not in content
    
    # Test 6: Error - text not found
    def test_text_not_found(self, temp_swift_file):
        """Test error when old_text doesn't exist"""
        result = edit_template_by_diff(
            old_text="nonexistent code",
            new_text="new code",
            start_line=1,
            end_line=5
        )
        
        assert "Error: Could not find exact match" in result
    
    # Test 7: Error - multiple occurrences
    def test_multiple_occurrences(self, temp_swift_file):
        """Test error when old_text appears multiple times"""
        result = edit_template_by_diff(
            old_text="func",
            new_text="function",
            start_line=1,
            end_line=13
        )
        
        assert "Error: Found" in result
        assert "occurrences" in result
    
    # Test 8: Error - invalid line numbers
    def test_invalid_line_numbers(self, temp_swift_file):
        """Test error handling for invalid line numbers"""
        # start_line too high
        result = edit_template_by_diff(
            old_text="test",
            new_text="new",
            start_line=100,
            end_line=101
        )
        assert "Error: Invalid start_line" in result
        
        # end_line too high
        result = edit_template_by_diff(
            old_text="test",
            new_text="new",
            start_line=1,
            end_line=100
        )
        assert "Error: Invalid end_line" in result
        
        # start_line > end_line
        result = edit_template_by_diff(
            old_text="test",
            new_text="new",
            start_line=10,
            end_line=5
        )
        assert "Error: start_line" in result
        assert "cannot be greater than end_line" in result
    
    # Test 9: Error - missing line parameters
    def test_missing_line_parameters(self, temp_swift_file):
        """Test error when start_line or end_line not provided"""
        result = edit_template_by_diff(
            old_text="test",
            new_text="new"
        )
        assert "Error: Must pass in a start_line AND end_line" in result
    
    # Test 10: Complex multi-line edit preserving indentation
    def test_complex_multi_line_with_indentation(self, temp_swift_file):
        """Test complex multi-line replacement preserving indentation"""
        result = edit_template_by_diff(
            old_text="""struct Template {
    var name: String
    var value: Int""",
            new_text="""struct Template {
    var name: String
    var value: Int
    var description: String
    var isActive: Bool = true""",
            start_line=2,
            end_line=4
        )
        
        assert "OK: Successfully updated" in result
        content = self.read_file(temp_swift_file)
        assert "var description: String" in content
        assert "var isActive: Bool = true" in content
        # Verify indentation preserved
        lines = content.splitlines()
        for line in lines:
            if "var description" in line:
                assert line.startswith("    ")  # 4 spaces

if __name__ == "__main__":
    pytest.main([__file__, "-v"])