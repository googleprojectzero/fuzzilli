import os
import sys
import subprocess
from clang import cindex
cindex.Config.set_library_file("/usr/lib/llvm-20/lib/libclang.so")
from clang.cindex import Index, CursorKind, Config
import json
from collections import defaultdict, deque
from pathlib import Path


class CFGNode:
    node_counter = 0
    
    def __init__(self, kind, location=None, content=None):
        self.id = CFGNode.node_counter
        CFGNode.node_counter += 1
        self.kind = kind
        self.location = location
        self.content = content
        self.successors = []
        self.predecessors = []
    
    def add_successor(self, node):
        if node not in self.successors:
            self.successors.append(node)
            node.predecessors.append(self)
    
    def __repr__(self):
        loc = f"{self.location['file']}:{self.location['line']}" if self.location else "unknown"
        return f"CFGNode(id={self.id}, kind={self.kind}, loc={loc})"
    
    def to_dict(self):
        return {
            'id': self.id,
            'kind': self.kind,
            'location': self.location,
            'content': self.content,
            'successors': [s.id for s in self.successors],
            'predecessors': [p.id for p in self.predecessors]
        }


class CFG:
    def __init__(self, function_name):
        self.function_name = function_name
        self.entry = None
        self.exit = None
        self.nodes = []
        self.current_node = None
    
    def add_node(self, kind, location=None, content=None):
        node = CFGNode(kind, location, content)
        self.nodes.append(node)
        return node
    
    def to_dict(self):
        return {
            'function_name': self.function_name,
            'entry': self.entry.id if self.entry else None,
            'exit': self.exit.id if self.exit else None,
            'nodes': [node.to_dict() for node in self.nodes]
        }


class CFGBuilder:
    def __init__(self, v8_src_path):
        self.v8_src_path = Path(v8_src_path)
        self.index = Index.create()
        self.cfgs = {}
        
    def get_location(self, cursor):
        if cursor.location.file:
            return {
                'file': cursor.location.file.name,
                'line': cursor.location.line,
                'column': cursor.location.column
            }
        return None
    
    def get_cursor_content(self, cursor):
        if cursor.extent.start.file and cursor.extent.end.file:
            try:
                with open(cursor.extent.start.file.name, 'r', encoding='utf-8', errors='ignore') as f:
                    lines = f.readlines()
                    if cursor.extent.start.line == cursor.extent.end.line:
                        line = lines[cursor.extent.start.line - 1]
                        return line[cursor.extent.start.column - 1:cursor.extent.end.column - 1].strip()
                    else:
                        content = []
                        for i in range(cursor.extent.start.line - 1, min(cursor.extent.end.line, len(lines))):
                            if i == cursor.extent.start.line - 1:
                                content.append(lines[i][cursor.extent.start.column - 1:])
                            elif i == cursor.extent.end.line - 1:
                                content.append(lines[i][:cursor.extent.end.column - 1])
                            else:
                                content.append(lines[i])
                        return ''.join(content).strip()
            except:
                pass
        return cursor.spelling or str(cursor.kind)
    
    def build_function_cfg(self, cursor, cfg):
        if cursor.kind == CursorKind.COMPOUND_STMT:
            return self.process_compound_stmt(cursor, cfg)
        
        node = cfg.add_node(
            kind=cursor.kind.name,
            location=self.get_location(cursor),
            content=self.get_cursor_content(cursor)
        )
        
        if cursor.kind == CursorKind.IF_STMT:
            return self.process_if_stmt(cursor, cfg, node)
        elif cursor.kind == CursorKind.WHILE_STMT:
            return self.process_while_stmt(cursor, cfg, node)
        elif cursor.kind == CursorKind.FOR_STMT:
            return self.process_for_stmt(cursor, cfg, node)
        elif cursor.kind == CursorKind.DO_STMT:
            return self.process_do_stmt(cursor, cfg, node)
        elif cursor.kind == CursorKind.SWITCH_STMT:
            return self.process_switch_stmt(cursor, cfg, node)
        elif cursor.kind == CursorKind.RETURN_STMT:
            return node, None
        elif cursor.kind == CursorKind.BREAK_STMT:
            return None, node
        elif cursor.kind == CursorKind.CONTINUE_STMT:
            return node, None
        else:
            return node, node
    
    def process_compound_stmt(self, cursor, cfg):
        children = list(cursor.get_children())
        if not children:
            return None, None
        
        first_entry = None
        last_exit = None
        prev_exit = None
        
        for child in children:
            entry, exit_node = self.build_function_cfg(child, cfg)
            
            if first_entry is None:
                first_entry = entry
            
            if prev_exit and entry:
                prev_exit.add_successor(entry)
            
            prev_exit = exit_node
            last_exit = exit_node
        
        return first_entry, last_exit
    
    def process_if_stmt(self, cursor, cfg, condition_node):
        children = list(cursor.get_children())
        
        if len(children) < 2:
            return condition_node, condition_node
        
        then_entry, then_exit = self.build_function_cfg(children[1], cfg)
        
        if then_entry:
            condition_node.add_successor(then_entry)
        
        merge_node = cfg.add_node('MERGE', self.get_location(cursor), 'if_merge')
        
        if then_exit:
            then_exit.add_successor(merge_node)
        
        if len(children) > 2:
            else_entry, else_exit = self.build_function_cfg(children[2], cfg)
            if else_entry:
                condition_node.add_successor(else_entry)
            if else_exit:
                else_exit.add_successor(merge_node)
        else:
            condition_node.add_successor(merge_node)
        
        return condition_node, merge_node
    
    def process_while_stmt(self, cursor, cfg, condition_node):
        children = list(cursor.get_children())
        
        if len(children) < 2:
            return condition_node, condition_node
        
        body_entry, body_exit = self.build_function_cfg(children[1], cfg)
        
        exit_node = cfg.add_node('LOOP_EXIT', self.get_location(cursor), 'while_exit')
        
        if body_entry:
            condition_node.add_successor(body_entry)
        
        if body_exit:
            body_exit.add_successor(condition_node)
        
        condition_node.add_successor(exit_node)
        
        return condition_node, exit_node
    
    def process_for_stmt(self, cursor, cfg, loop_node):
        children = list(cursor.get_children())
        
        if not children:
            return loop_node, loop_node
        
        body_entry, body_exit = self.build_function_cfg(children[-1], cfg)
        
        exit_node = cfg.add_node('LOOP_EXIT', self.get_location(cursor), 'for_exit')
        
        if body_entry:
            loop_node.add_successor(body_entry)
        
        if body_exit:
            body_exit.add_successor(loop_node)
        
        loop_node.add_successor(exit_node)
        
        return loop_node, exit_node
    
    def process_do_stmt(self, cursor, cfg, do_node):
        children = list(cursor.get_children())
        
        if not children:
            return do_node, do_node
        
        body_entry, body_exit = self.build_function_cfg(children[0], cfg)
        
        condition_node = cfg.add_node('DO_CONDITION', self.get_location(cursor), 'do_condition')
        exit_node = cfg.add_node('LOOP_EXIT', self.get_location(cursor), 'do_exit')
        
        if body_entry:
            do_node.add_successor(body_entry)
        
        if body_exit:
            body_exit.add_successor(condition_node)
        
        condition_node.add_successor(do_node)
        condition_node.add_successor(exit_node)
        
        return do_node, exit_node
    
    def process_switch_stmt(self, cursor, cfg, switch_node):
        children = list(cursor.get_children())
        
        if len(children) < 2:
            return switch_node, switch_node
        
        merge_node = cfg.add_node('MERGE', self.get_location(cursor), 'switch_merge')
        
        for child in children[1:]:
            if child.kind in [CursorKind.CASE_STMT, CursorKind.DEFAULT_STMT]:
                case_children = list(child.get_children())
                if case_children:
                    case_entry, case_exit = self.build_function_cfg(case_children[-1], cfg)
                    if case_entry:
                        switch_node.add_successor(case_entry)
                    if case_exit:
                        case_exit.add_successor(merge_node)
        
        switch_node.add_successor(merge_node)
        
        return switch_node, merge_node
    
    def process_function(self, cursor):
        if cursor.kind not in [CursorKind.FUNCTION_DECL, CursorKind.CXX_METHOD]:
            return None
        
        if not cursor.is_definition():
            return None
        
        function_name = cursor.spelling
        cfg = CFG(function_name)
        
        cfg.entry = cfg.add_node('ENTRY', self.get_location(cursor), f'Entry: {function_name}')
        cfg.exit = cfg.add_node('EXIT', self.get_location(cursor), f'Exit: {function_name}')
        
        body = None
        for child in cursor.get_children():
            if child.kind == CursorKind.COMPOUND_STMT:
                body = child
                break
        
        if body:
            body_entry, body_exit = self.process_compound_stmt(body, cfg)
            
            if body_entry:
                cfg.entry.add_successor(body_entry)
            else:
                cfg.entry.add_successor(cfg.exit)
            
            if body_exit:
                body_exit.add_successor(cfg.exit)
        else:
            cfg.entry.add_successor(cfg.exit)
        
        return cfg
    
    def traverse_ast(self, cursor):
        if cursor.kind in [CursorKind.FUNCTION_DECL, CursorKind.CXX_METHOD]:
            cfg = self.process_function(cursor)
            if cfg:
                full_name = f"{cursor.location.file.name}::{cursor.spelling}" if cursor.location.file else cursor.spelling
                self.cfgs[full_name] = cfg
        
        for child in cursor.get_children():
            self.traverse_ast(child)
    
    def parse_file(self, file_path, compile_args=None):
        if compile_args is None:
            compile_args = [
                '-x', 'c++',
                '-std=c++17',
                '-I' + str(self.v8_src_path),
                '-I' + str(self.v8_src_path / 'include'),
                '-DNDEBUG',
                '-DV8_INTL_SUPPORT',
            ]
        
        try:
            tu = self.index.parse(str(file_path), args=compile_args)
            
            if tu.diagnostics:
                severe_errors = [d for d in tu.diagnostics if d.severity >= 3]
                if severe_errors:
                    print(f"Parsing {file_path} with errors (continuing anyway)")
            
            self.traverse_ast(tu.cursor)
            return True
            
        except Exception as e:
            print(f"Error parsing {file_path}: {e}")
            return False
    
    def parse_directory(self, directory_path, pattern='*.cc'):
        dir_path = Path(directory_path)
        files = list(dir_path.rglob(pattern))
        
        print(f"Found {len(files)} files matching {pattern}")
        
        for i, file_path in enumerate(files):
            if i % 10 == 0:
                print(f"Processing {i}/{len(files)}: {file_path.name}")
            self.parse_file(file_path)
        
        print(f"Completed parsing. Found {len(self.cfgs)} function CFGs")
    
    def export_cfgs(self, output_path):
        output = {
            'total_functions': len(self.cfgs),
            'cfgs': {name: cfg.to_dict() for name, cfg in self.cfgs.items()}
        }
        
        with open(output_path, 'w') as f:
            json.dump(output, f, indent=2)
        
        print(f"Exported CFGs to {output_path}")
    
    def print_summary(self):
        print(f"\n{'='*80}")
        print(f"CFG Analysis Summary")
        print(f"{'='*80}")
        print(f"Total functions analyzed: {len(self.cfgs)}")
        
        if self.cfgs:
            total_nodes = sum(len(cfg.nodes) for cfg in self.cfgs.values())
            print(f"Total CFG nodes: {total_nodes}")
            print(f"Average nodes per function: {total_nodes / len(self.cfgs):.2f}")
            
            print(f"\nSample functions:")
            for i, (name, cfg) in enumerate(list(self.cfgs.items())[:5]):
                print(f"  {i+1}. {cfg.function_name} - {len(cfg.nodes)} nodes")



    def get_function_cfg(self, function_name):
        matching_cfgs = []
        for full_name, cfg in self.cfgs.items():
            if function_name in full_name or cfg.function_name == function_name:
                matching_cfgs.append((full_name, cfg))
        
        if not matching_cfgs:
            return None
        
        if len(matching_cfgs) > 1:
            print(f"Warning: Found {len(matching_cfgs)} functions matching '{function_name}'")
            print("Matches:")
            for i, (name, _) in enumerate(matching_cfgs):
                print(f"  {i+1}. {name}")
            print("Returning the first match")
        
        _, cfg = matching_cfgs[0]
        
        node_map = {node.id: node for node in cfg.nodes}
        
        visited = set()
        
        def build_tree(node_id, visited_in_path=None):
            if visited_in_path is None:
                visited_in_path = set()
            
            if node_id in visited:
                return {
                    'id': node_id,
                    'kind': node_map[node_id].kind,
                    'content': node_map[node_id].content,
                    'location': node_map[node_id].location,
                    'is_backedge': True,
                    'children': []
                }
            
            if node_id in visited_in_path:
                return {
                    'id': node_id,
                    'kind': node_map[node_id].kind,
                    'content': node_map[node_id].content,
                    'location': node_map[node_id].location,
                    'is_cycle': True,
                    'children': []
                }
            
            visited.add(node_id)
            visited_in_path.add(node_id)
            
            node = node_map[node_id]
            
            tree_node = {
                'id': node.id,
                'kind': node.kind,
                'content': node.content,
                'location': node.location,
                'children': []
            }
            
            for successor in node.successors:
                child_tree = build_tree(successor.id, visited_in_path.copy())
                tree_node['children'].append(child_tree)
            
            return tree_node
        
        if cfg.entry:
            tree = build_tree(cfg.entry.id)
        else:
            tree = {'error': 'No entry node found'}
        
        return {
            'function_name': cfg.function_name,
            'entry_id': cfg.entry.id if cfg.entry else None,
            'exit_id': cfg.exit.id if cfg.exit else None,
            'total_nodes': len(cfg.nodes),
            'tree': tree
        }




    
    def load_from_json(self, json_path):
        """
        Load previously exported CFGs from a JSON file.
        
        Args:
            json_path: Path to the JSON file containing CFG data
        
        Returns:
            Number of CFGs loaded
        """
        with open(json_path, 'r') as f:
            data = json.load(f)
        
        self.cfgs = {}
        
        for full_name, cfg_data in data.get('cfgs', {}).items():
            cfg = CFG(cfg_data['function_name'])
            
            node_map = {}
            for node_data in cfg_data['nodes']:
                node = CFGNode(
                    kind=node_data['kind'],
                    location=node_data['location'],
                    content=node_data['content']
                )
                node.id = node_data['id']
                node_map[node.id] = node
                cfg.nodes.append(node)
            
            for node_data in cfg_data['nodes']:
                node = node_map[node_data['id']]
                for succ_id in node_data['successors']:
                    if succ_id in node_map:
                        node.successors.append(node_map[succ_id])
                for pred_id in node_data['predecessors']:
                    if pred_id in node_map:
                        node.predecessors.append(node_map[pred_id])
            
            if cfg_data.get('entry') is not None:
                cfg.entry = node_map.get(cfg_data['entry'])
            if cfg_data.get('exit') is not None:
                cfg.exit = node_map.get(cfg_data['exit'])
            
            self.cfgs[full_name] = cfg
        
        print(f"Loaded {len(self.cfgs)} function CFGs from {json_path}")
        return len(self.cfgs)



def main():
    if len(sys.argv) < 2:
        print("Usage: python cfg_test.py <path_to_v8_src> [output_json]")
        print("Example: python cfg_test.py /path/to/v8/src cfg_output.json")
        sys.exit(1)
    
    v8_src_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else 'v8_cfg_output.json'
    
    if not os.path.exists(v8_src_path):
        print(f"Error: Path {v8_src_path} does not exist")
        sys.exit(1)
    
    print(f"Building CFG for V8 source code at: {v8_src_path}")
    
    builder = CFGBuilder(v8_src_path)
    
    if os.path.isfile(v8_src_path):
        builder.parse_file(v8_src_path)
    else:
        builder.parse_directory(v8_src_path, pattern='*.cc')
    
    builder.print_summary()
    builder.export_cfgs(output_path)


if __name__ == '__main__':
    main()





