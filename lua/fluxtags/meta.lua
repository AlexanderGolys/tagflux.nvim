---@meta
---@brief [[
--- Strongly typed API surface for fluxtags.nvim.
--- This file aggregates class and module signatures used across the runtime.
--- It is intended for editor language tooling and does not run plugin logic.
--- Conventions follow the declaration-first Luadoc style used in snacks-style
--- plugins: module tables + class/type annotations only, no implementation.
---@brief

--==============================================================================
-- Shared primitives
--==============================================================================

---@alias FluxtagsKindName string
---@alias FluxtagsKindFile table<string, { file:string, lnum:number, col?:number }[]>
---@alias FluxtagsTagFileLine string

---@class ConcealSpec
---@field offset number Byte offset from match start.
---@field length number Number of bytes to cover.
---@field char? string Conceal replacement char.
---@field hl_group? string Highlight override for this segment.
---@field priority? number Priority override for this segment.

---@class TagKind
---@field name string
---@field pattern string Lua pattern containing capture for the tag text.
---@field hl_group string
---@field conceal_pattern? fun(name: string): ConcealSpec[]
---@field save_to_tagfile boolean
---@field tagfile? string
---@field priority number
---@field on_jump fun(name: string, ctx: table): boolean
---@field on_enter? fun(bufnr: number, lines: string[])
---@field extract_name? fun(capture: string): string
---@field is_valid? fun(name: string): boolean
---@field apply_extmarks? fun(self: TagKind, bufnr: number, lnum: number, line: string, ns: number, is_disabled?: fun(lnum:number, col:number): boolean)
---@field apply_diagnostics? fun(self: TagKind, bufnr: number, lines: string[], is_disabled?: fun(lnum:number, col:number): boolean)
---@field collect_tags? fun(self: TagKind, filepath: string, lines: string[], is_disabled?: fun(lnum:number, col:number): boolean): {name:string,file:string,lnum:number,col?:number}[]
---@field find_at_cursor? fun(self: TagKind, line: string, col: number): string?, number?, number?
---@field get_disabled_intervals? fun(self: TagKind, lines: string[], directive_name: string): table[]

---@class TagKindOptions
---@field name FluxtagsKindName
---@field pattern string
---@field hl_group? string
---@field conceal_pattern? fun(name: string): ConcealSpec[]
---@field save_to_tagfile? boolean
---@field tagfile? string
---@field priority? number
---@field on_jump? fun(name: string, ctx: table): boolean
---@field on_enter? fun(bufnr: number, lines: string[])
---@field extract_name? fun(capture: string): string
---@field is_valid? fun(name: string): boolean
---@field apply_extmarks? fun(self: TagKind, bufnr: number, lnum: number, line: string, ns: number, is_disabled?: fun(lnum:number, col:number): boolean)
---@field apply_diagnostics? fun(self: TagKind, bufnr: number, lines: string[], is_disabled?: fun(lnum:number, col:number): boolean)
---@field collect_tags? fun(self: TagKind, filepath: string, lines: string[], is_disabled?: fun(lnum:number, col:number): boolean): {name:string,file:string,lnum:number,col?:number}[]
---@field find_at_cursor? fun(self: TagKind, line: string, col: number): string?, number?, number?
---@field get_disabled_intervals? fun(self: TagKind, lines: string[], directive_name: string): table[]

---@class TagKindMethods
---@field apply_extmarks? fun(self: TagKind, bufnr: number, lnum: number, line: string, ns: number, is_disabled?: fun(lnum:number, col:number): boolean)
---@field apply_diagnostics? fun(self: TagKind, bufnr: number, lines: string[], is_disabled?: fun(lnum:number, col:number): boolean)
---@field collect_tags? fun(self: TagKind, filepath: string, lines: string[], is_disabled?: fun(lnum:number, col:number): boolean): {name:string,file:string,lnum:number,col?:number}[]
---@field find_at_cursor? fun(self: TagKind, line: string, col: number): string?, number?, number?
---@field get_disabled_intervals? fun(self: TagKind, lines: string[], directive_name: string): table[]

---@class TagKindBuilder
---@field _opts TagKindOptions
---@field with fun(self: TagKindBuilder, key:string, value:any): TagKindBuilder
---@field with_name fun(self: TagKindBuilder, name: FluxtagsKindName): TagKindBuilder
---@field with_pattern fun(self: TagKindBuilder, pattern: string): TagKindBuilder
---@field with_hl_group fun(self: TagKindBuilder, hl_group: string): TagKindBuilder
---@field with_priority fun(self: TagKindBuilder, priority:number?): TagKindBuilder
---@field with_tagfile fun(self: TagKindBuilder, tagfile:string?): TagKindBuilder
---@field save_to_tagfile fun(self: TagKindBuilder, enabled:boolean?): TagKindBuilder
---@field with_extract_name fun(self: TagKindBuilder, fn:fun(capture:string):string): TagKindBuilder
---@field with_on_jump fun(self: TagKindBuilder, fn:fun(name:string, ctx:table):boolean): TagKindBuilder
---@field with_on_enter fun(self: TagKindBuilder, fn:fun(bufnr:number, lines:string[]):any): TagKindBuilder
---@field with_is_valid fun(self: TagKindBuilder, fn:fun(name:string):boolean): TagKindBuilder
---@field with_conceal_pattern fun(self: TagKindBuilder, fn:fun(name:string):ConcealSpec[]): TagKindBuilder
---@field with_methods fun(self: TagKindBuilder, methods:TagKindMethods): TagKindBuilder
---@field build fun(self: TagKindBuilder): TagKind

---@class TagKindEntry
---@field name string
---@field module string
---@field optional boolean
---@field config_key string
---@field register fun(self: TagKindEntry, fluxtags:fluxtags): boolean

---@class TagKindRegistry
---@field entries TagKindEntry[]
---@field add fun(self: TagKindRegistry, name: string, module: string, opts?: table): TagKindRegistry
---@field register_all fun(self: TagKindRegistry, fluxtags: fluxtags): nil

---@class FluxtagsKindHelpItem
---@field syntax string
---@field info string

---@class FluxtagsExtmark
---@field bufnr integer
---@field ns integer
---@field lnum integer
---@field col integer
---@field opts vim.api.keyset.set_extmark
---@field api table

---@class FluxtagsPath
---@field fn table

---@class FluxtagsDiagnostic
---@field bufnr number
---@field lnum number
---@field col number
---@field end_col number
---@field severity number
---@field source string
---@field message string

---@class FluxtagsDiagnosticParams
---@field diags vim.Diagnostic[]
---@field bufnr integer
---@field lnum integer
---@field col integer
---@field end_col integer
---@field severity integer
---@field source string
---@field message_prefix string
---@field name string

---@class CfgDirective
---@field s number
---@field e number
---@field key string
---@field value string
---@field tag_end number

---@class CfgDirectiveSpec
---@field key string
---@field description string

---@class FluxtagsTagEntry
---@field file string
---@field lnum integer
---@field col? integer

---@class FluxtagsTagStore: table<string, FluxtagsTagEntry[]>

---@class TagKindRuntime
---@field fluxtags fluxtags
---@field new fun(fluxtags:fluxtags): TagKindRuntime
---@field load fun(self: TagKindRuntime, kind_name: string): FluxtagsKindFile
---@field warn fun(self: TagKindRuntime, message:string): nil
---@field jump_to_first fun(self: TagKindRuntime, kind_name:string, name:string, ctx:table, not_found_prefix:string): boolean
---@field pick_tag_locations fun(self: TagKindRuntime, kind_name:string, name:string, ctx:table, missing_message:string, title_prefix:string): boolean
---@field push_missing_tag_diagnostic fun(self: TagKindRuntime, params: FluxtagsDiagnosticParams): nil

---@class PrefixedKindExtmarkOptions
---@field open? string
---@field close? string
---@field conceal_open? string
---@field conceal_close? string

---@class PrefixedKindBinder
---@field fluxtags table
---@field kind_name string
---@field cfg table
---@field opts table
---@field prefix_patterns string[]
---@field pattern string
---@field kind_builder fun(self: PrefixedKindBinder, overrides?: TagKindOptions): TagKindBuilder
---@field new_kind fun(self: PrefixedKindBinder, opts: TagKindOptions): TagKind
---@field attach_find_at_cursor fun(self: PrefixedKindBinder, kind: TagKind, inline_pattern?: string): nil
---@field attach_prefixed_extmarks fun(self: PrefixedKindBinder, kind: TagKind, ext_opts: PrefixedKindExtmarkOptions): nil

---@class KindConfig
---@field name string
---@field tagfile? string
---@field filetypes_inc? string[]
---@field filetypes_exc? string[]
---@field hl_group? string

---@class GlobalConfig
---@field filetypes_inc? string[]
---@field filetypes_exc? string[]

---@class Config
---@field filetypes_inc? string[]
---@field filetypes_exc? string[]
---@field filetypes_whitelist? string[]
---@field filetypes_ignore? string[]
---@field kinds? table<string, KindConfig>
---@field highlights? table<string, string|vim.api.keyset.highlight>

---@class FluxtagsCommands
---@field private fluxtags fluxtags
---@field private ns number
---@field private tag_kinds table<string, TagKind>
---@field private load_tagfile fun(kind_name: string): FluxtagsKindFile
---@field private prune_tagfile fun(kind_name: string): integer
---@field private setup_buffer fun(bufnr: integer|nil, force: boolean)
---@field private config_mod table
---@field new fun(fluxtags:fluxtags): FluxtagsCommands
---@field _register fun(self: FluxtagsCommands, name:string, callback:fun(opts:vim.api.keyset.user_command), opts:vim.api.keyset.user_command): nil
---@field setup fun(self: FluxtagsCommands): nil

---@class FluxtagsApp
---@field config Config
---@field ns integer
---@field diag_ns integer
---@field tag_kinds table<string, TagKind>
---@field kind_order string[]
---@field kind_registry TagKindRegistry
---@field tag_cache table<string, FluxtagsKindFile>
---@field utils table
---@field ordered_kinds fun(self: FluxtagsApp): fun(): string, TagKind
---@field should_process_buf fun(self: FluxtagsApp, bufnr: integer): boolean
---@field register_kind fun(self: FluxtagsApp, kind: TagKind): boolean
---@field load_tagfile fun(self: FluxtagsApp, kind_name: string): FluxtagsKindFile
---@field write_tagfile fun(self: FluxtagsApp, kind_name: string, filepath: string, new_tags: {name:string,file:string,lnum:number,col?:number}[]): { added:integer, removed:integer, modified:integer }
---@field prune_tagfile fun(self: FluxtagsApp, kind_name: string): integer
---@field open_file fun(self: FluxtagsApp, path: string, ctx?: table): nil
---@field load_tags fun(self: FluxtagsApp, kind_name: string): FluxtagsKindFile
---@field load_all_tags fun(self: FluxtagsApp): integer
---@field redraw_extmarks fun(self: FluxtagsApp, bufnr?: integer): nil
---@field jump_to_tag fun(self: FluxtagsApp): nil
---@field update_tags fun(self: FluxtagsApp, silent:boolean, bufnr?:integer): nil
---@field run_on_enter_hooks fun(self: FluxtagsApp, bufnr: integer): nil
---@field setup_buffer fun(self: FluxtagsApp, bufnr?: integer, force?: boolean): nil
---@field schedule_refresh fun(self: FluxtagsApp, bufnr: integer): nil
---@field setup fun(self: FluxtagsApp, opts?: Config): nil

--==============================================================================
-- fluxtags module
--==============================================================================

---@class fluxtags
local fluxtags = {}

---@field setup fun(opts?: Config)
---@field load_tagfile fun(kind_name: string): FluxtagsKindFile
---@field prune_tagfile fun(kind_name: string): integer
---@field load_tags fun(kind_name: string): FluxtagsKindFile
---@field load_all_tags fun(): integer
---@field jump_to_tag fun(): nil
---@field register_kind fun(kind: TagKind): boolean
---@field update_tags fun(silent: boolean, bufnr?: integer): nil
---@field setup_buffer fun(bufnr?: integer, force?: boolean): nil
---@field tag_kinds table<string, TagKind>
---@field config Config
---@field utils table

--==============================================================================
-- Core constructors
--==============================================================================

---@class tag_kind
local tag_kind = {}

---@param opts TagKindOptions|TagKindBuilder
---@return TagKind
function tag_kind.new(opts) end

---@param opts TagKindOptions
---@return TagKindBuilder
function tag_kind.builder(opts) end

---@class tag_kind.Builder: TagKindBuilder
tag_kind.Builder = {} ---@type TagKindBuilder

---@class tag_kind.TagKind: TagKind
tag_kind.TagKind = {} ---@type TagKind

--==============================================================================
-- Module APIs
--==============================================================================

---@class fluxtags_config
local fluxtags_config = {}

---@type table<string, KindConfig>
fluxtags_config.defaults = {}
---@type GlobalConfig
fluxtags_config.global_defaults = {}
---@param kind string
---@param user_overrides? table<string, KindConfig>
---@return KindConfig
function fluxtags_config.get(kind, user_overrides) end
---@param kind string
---@param user_overrides? table<string, KindConfig>
---@return string|nil
function fluxtags_config.get_tagfile(kind, user_overrides) end
---@param kind string
---@return string
function fluxtags_config.default_tagfile(kind) end
---@param kind string
---@param user_overrides? table<string, KindConfig>
---@return string
function fluxtags_config.get_hl_group(kind, user_overrides) end
---@param user_highlights? table<string, string|vim.api.keyset.highlight>
function fluxtags_config.setup_default_highlights(user_highlights) end

---@class tagkinds_registry
local tagkinds_registry = {}
---@return TagKindRegistry
function tagkinds_registry.builtins() end

---@class tagkinds_prefixed_kind
local tagkinds_prefixed_kind = {}
---@param fluxtags fluxtags
---@param kind_name string
---@param defaults table
---@return PrefixedKindBinder
function tagkinds_prefixed_kind.binder(fluxtags, kind_name, defaults) end
---@param fluxtags fluxtags
---@param kind_name string
---@param defaults table
---@return PrefixedKindBinder
function tagkinds_prefixed_kind.factory(fluxtags, kind_name, defaults) end
---@param fluxtags fluxtags
---@param kind_name string
---@param defaults table
---@return table cfg
---@return table opts
function tagkinds_prefixed_kind.resolve(fluxtags, kind_name, defaults) end
---@param kind TagKind
---@param pattern string
---@param prefix_patterns string[]
---@param inline_pattern? string
---@return nil
function tagkinds_prefixed_kind.attach_find_at_cursor(kind, pattern, prefix_patterns, inline_pattern) end
---@param kind TagKind
---@param pattern string
---@param prefix_patterns string[]
---@param ext_opts table
---@return nil
function tagkinds_prefixed_kind.attach_prefixed_extmarks(kind, pattern, prefix_patterns, ext_opts) end
---@param opts table
---@return TagKind
function tagkinds_prefixed_kind.new_kind(opts) end

---@class fluxtags_common
local fluxtags_common = {}
---@field NAME_CHARS string
---@field INLINE_SUBTAG_PATTERN string
---@param fluxtags fluxtags
---@param kind_name string
---@param defaults table<string, any>
---@param default_prefix_patterns? string[]
---@return table cfg
---@return table resolved
function fluxtags_common.resolve_kind_config(fluxtags, kind_name, defaults, default_prefix_patterns) end
---@param name string
---@return boolean
function fluxtags_common.is_valid_name(name) end
---@param pattern string
---@param fallback string
---@return string
function fluxtags_common.derive_open(pattern, fallback) end

---@class fluxtags_extmark
local fluxtags_extmark = {}
---@param bufnr integer
---@param ns? integer
---@param lnum integer
---@param col integer
---@param opts? vim.api.keyset.set_extmark
---@param api? table
---@return FluxtagsExtmark
function fluxtags_extmark.new(bufnr, ns, lnum, col, opts, api) end
---@param bufnr integer
---@param ns? integer
---@param lnum integer
---@param col integer
---@param opts? vim.api.keyset.set_extmark
---@param api? table
---@return boolean ok
---@return integer|string result
function fluxtags_extmark.place(bufnr, ns, lnum, col, opts, api) end

---@class fluxtags_path
local fluxtags_path = {}
---@param fn? table
---@return FluxtagsPath
function fluxtags_path.new(fn) end

---@class fluxtags_prefix
local fluxtags_prefix = {}
---@field default_comment_prefix_patterns string[]
---@param line string
---@param marker_start number
---@param prefix_patterns? string[]
---@return number
---@return string
function fluxtags_prefix.find_prefix(line, marker_start, prefix_patterns) end
---@param line string
---@param col number
---@param pattern string
---@param prefix_patterns? string[]
---@return string|nil
---@return number|nil
---@return number|nil
function fluxtags_prefix.find_tag_at_cursor(line, col, pattern, prefix_patterns) end
---@param line string
---@param col number
---@param pattern string
---@return string|nil
---@return number|nil
---@return number|nil
function fluxtags_prefix.find_match_at_cursor(line, col, pattern) end
---@param bufnr number
---@param ns number
---@param lnum number
---@param line string
---@param pattern string
---@param prefix_patterns? string[]
---@param opts table
---@param is_disabled? fun(lnum:number, col:number): boolean
function fluxtags_prefix.apply_prefixed_extmarks(bufnr, ns, lnum, line, pattern, prefix_patterns, opts, is_disabled) end

---@class fluxtags_picker
local fluxtags_picker = {}
---@param entries {file:string,lnum:number,col?:number}[]
---@param title string
---@param ctx table
function fluxtags_picker.pick_locations(entries, title, ctx) end

---@class fluxtags_jump
local fluxtags_jump = {}
---@param name string
---@return string
function fluxtags_jump.base_name(name) end
---@param tags table<string, table[]>
---@param name string
---@return table[]|nil
---@return string
function fluxtags_jump.find_entries(tags, name) end
---@param search_name string
---@param fallback_name string
---@param entry {file:string,lnum:number,col?:number}
---@param ctx table
---@return boolean
function fluxtags_jump.jump_to_entry(search_name, fallback_name, entry, ctx) end

---@class fluxtags_autocmds
local fluxtags_autocmds = {}
---@param fluxtags fluxtags
---@param schedule_refresh fun(bufnr: number)
function fluxtags_autocmds.setup(fluxtags, schedule_refresh) end

---@class fluxtags_diagnostics
local fluxtags_diagnostics = {}
---@param diags vim.Diagnostic[]
---@param bufnr number
---@param lnum number
---@param col number
---@param end_col number
---@param severity integer
---@param source string
---@param message string
function fluxtags_diagnostics.push(diags, bufnr, lnum, col, end_col, severity, source, message) end
---@param bufnr number
---@param ns number
---@param diags vim.Diagnostic[]
---@param set_diagnostics fun(bufnr:number, ns:number, diags:vim.Diagnostic[])
function fluxtags_diagnostics.publish(bufnr, ns, diags, set_diagnostics) end
---@param bufnr number
---@param ns number
---@param lnum number
---@param col number
---@param end_col number
---@param priority number
function fluxtags_diagnostics.error_extmark(bufnr, ns, lnum, col, end_col, priority) end

---@class tagkinds_cfg_parser
local tagkinds_cfg_parser = {}
---@param line string
---@param search_pattern string
---@param parse_args boolean
---@return CfgDirective[]
function tagkinds_cfg_parser.parse_line(line, search_pattern, parse_args) end
---@param lines string[]
---@param parse_line fun(line:string): CfgDirective[]
---@param directive_name string
---@return table[]
function tagkinds_cfg_parser.disabled_intervals(lines, parse_line, directive_name) end

---@class tagkinds_cfg_registry
local tagkinds_cfg_registry = {}
---@return string[]
function tagkinds_cfg_registry.known_keys() end
---@return CfgDirectiveSpec[]
function tagkinds_cfg_registry.info() end
---@param key string
---@param handler fun(value:string, bufnr:number)
---@param description? string
function tagkinds_cfg_registry.register(key, handler, description) end
---@param key string
---@return boolean
function tagkinds_cfg_registry.has(key) end
---@param key string
---@param value string
---@param bufnr number
---@return boolean
---@return string?
function tagkinds_cfg_registry.exec(key, value, bufnr) end

---@class fluxtags_commands_tags_picker
local fluxtags_commands_tags_picker = {}
---@param title string
---@param items {text:string, ordinal?:string}[]
---@return boolean
function fluxtags_commands_tags_picker.pick_static_items(title, items) end
---@param tag_kinds table<string, TagKind>
---@param load_tagfile fun(kind_name: string): FluxtagsKindFile
---@param kind_filter? string
---@return table[]
function fluxtags_commands_tags_picker.collect_entries(tag_kinds, load_tagfile, kind_filter) end
---@param title string
---@param entries table[]
---@param on_confirm fun(entry: table)
function fluxtags_commands_tags_picker.pick_tag_entries(title, entries, on_confirm) end
---@param fluxtags fluxtags
---@param tag_kinds table<string, TagKind>
---@param entry {kind:string,name:string,file:string,lnum:number}
function fluxtags_commands_tags_picker.jump_to_picker_entry(fluxtags, tag_kinds, entry) end

---@class fluxtags_commands_kind_help
local fluxtags_commands_kind_help = {}
---@alias FluxtagsKind "mark"|"ref"|"refog"|"bib"|"og"|"hl"|"cfg"
---@return FluxtagsKind[]
function fluxtags_commands_kind_help.preview_kinds() end
---@return table<FluxtagsKind, FluxtagsKindHelpItem>
function fluxtags_commands_kind_help.kind_help() end
---@param kind string
---@return boolean
function fluxtags_commands_kind_help.notify_kind_help(kind) end
---@param kind FluxtagsKind|string
---@return string
function fluxtags_commands_kind_help.kind_symbol(kind) end

---@class fluxtags_commands_tree
local fluxtags_commands_tree = {}
---@param load_tagfile fun(kind_name:string):FluxtagsKindFile
---@param output_file? string
function fluxtags_commands_tree.generate(load_tagfile, output_file) end

---@class fluxtags_commands_debug
local fluxtags_commands_debug = {}
---@param ns number
---@param tag_kinds table<string, TagKind>
function fluxtags_commands_debug.setup(ns, tag_kinds) end

---@class fluxtags_commands
local fluxtags_commands = {}
---@param fluxtags fluxtags
function fluxtags_commands.setup(fluxtags) end

---@class fluxtags_runtime
local fluxtags_runtime = {}
---@param fluxtags fluxtags
---@return TagKindRuntime
function fluxtags_runtime.new(fluxtags) end

---@class FluxtagsKindBuiltin
local kind_mark = {}
---@param fluxtags fluxtags
function kind_mark.register(fluxtags) end
local kind_ref = {}
---@param fluxtags fluxtags
function kind_ref.register(fluxtags) end
local kind_refog = {}
---@param fluxtags fluxtags
function kind_refog.register(fluxtags) end
local kind_bib = {}
---@param fluxtags fluxtags
function kind_bib.register(fluxtags) end
local kind_og = {}
---@param fluxtags fluxtags
function kind_og.register(fluxtags) end
local kind_hl = {}
---@param fluxtags fluxtags
function kind_hl.register(fluxtags) end
local kind_cfg = {}
---@param fluxtags fluxtags
function kind_cfg.register(fluxtags) end
---@param fluxtags fluxtags
function kind_cfg.known_keys() end
---@return {key:string, description:string}[]
function kind_cfg.get_directives_info() end
---@param key string
---@param handler fun(value:string, bufnr:number)
---@param description? string
function kind_cfg.register_handler(key, handler, description) end

return fluxtags
