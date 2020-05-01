--[[ This Source Code Form is subject to the terms of the Mozilla Public
     License, v. 2.0. If a copy of the MPL was not distributed with this
     file, You can obtain one at https://mozilla.org/MPL/2.0/. ]]

local indent = '   '
local subindent = indent:sub(1, #indent-1)

local ins = require 'inspect'
local lpeg_raylib_reader = require 'binding_generator/lpeg-raylib-reader'

local function typecheck_assert(value, _types)
   local valuetype = type(value)
   local result = false

   for i = 1, #_types do
      result = result or valuetype == _types[i]
   end

   if not result then
      local msg = "typechecking assert: '" .. table.concat(_types, "' or '") .. "' expected, got '" .. valuetype .. "' (value: '" .. tostring(value) .. "')"
      error(msg, 2)
   end

   return value
end

-- returns {...} (like table.pack) with the following metatable:
-- __index: set result_mt as __index, result_mt contains useful methods:
--          -> insert(self, str): works like table.insert, it also verifies if str is a string
--          -> concat(self): returns table.concat(self, ' '), for example: {'x', 'y'} -> "x y"
-- __newindex: does typechecking when inserting a new index on result table,
--             so trying to insert a non-number field or non-string value will trigger an error.

local function new_result(...)
   local result = {}

   local result_mt = {
      insert = function(self, str)
         self[#self+1] = typecheck_assert(str, {'string'})
      end,
      concat = function(self)
         typecheck_assert(self, {'table'})
         return table.concat(self, ' ')
      end,
   }

   setmetatable(result, {
      __newindex = function(tbl, key, value)
         rawset(
            tbl,
            typecheck_assert(key, {'number'}),
            typecheck_assert(value, {'string'})
         )
      end,
      __index = result_mt
   })

   local pre_values = {...}
   table.move(pre_values, 1, #pre_values, 1, result)

   return result
end

local converters = {}

local function traverse(values)
   local result = new_result()
   for i = 1, #values do
      print('traversing ' .. i .. ' ~> ' .. values[i].name)
      local value_result = converters.convert(values[i].value):concat()
      result:insert(value_result)
   end
   return result
end

function converters.empty_space(value)
   return new_result(value)
end

function converters.parentheses(value)
   return new_result(value)
end

function converters.literal(value)
   return new_result(value)
end

function converters.arithmetic_expr(value)
   return new_result(traverse(value):concat())
end

function converters.comment(value)
   return new_result('--', value)
end

function converters.identifier(value)
   return new_result(value)
end

function converters.define_replacement(value)
   return new_result(traverse(value):concat())
end

function converters.define(value)
   return new_result('global', traverse(value):concat(), '\n')
end

function converters.convert(subject)
   print('subject: ', subject)
   local result = new_result()

   if type(subject) == 'string' then
      print('subject is string: ' .. subject)
      result:insert(subject)
   elseif type(subject) == 'table' then
      for i = 1, #subject do
         print('trying to convert subject: ' .. subject[i].name)
         local converter = converters[subject[i].name]
         if converter then
            print ('converting subsubject [' .. i .. '] -> ' .. subject[i].name)
            result:insert(converter(subject[i].value):concat())
         else
            print ('**FAIL** to convert subsubject [' .. i .. '] -> ' .. subject[i].name)
         end
      end
   end

   return result
end

local linklibs = {
   'raylib',
   'GL',
   'glfw',
   'openal',
   'm',
   'pthread',
   'dl',
   'X11',
   'Xrandr',
   'Xinerama',
   'Xi',
   'Xxf86vm',
   'Xcursor'
}

local cincludes = {
   '<raylib.h>', '<raymath.h>'
}

local raylib_table = lpeg_raylib_reader.read'binding_generator/modified-raylib.h'
local raylib_result = converters.convert(raylib_table)

print ("#raylib_table " .. #raylib_table)

local final_result = {}

table.insert(final_result, '-- links: \n')

for i = 1, #linklibs do
   table.insert(final_result, "## linklib '" .. linklibs[i] .. "' \n")
end

table.insert(final_result, '\n-- includes: \n')

for i = 1, #cincludes do
   table.insert(final_result, "## cinclude '" .. cincludes[i] .. "' \n")
end

table.insert(final_result, '\n-- raylib binding: \n')

for i = 1, #raylib_result do
   table.insert(final_result, raylib_result[i])
end

table.insert(final_result, '')

local file_to_generate = io.open('raylib.nelua', 'w+')
file_to_generate:write(table.concat(final_result))
file_to_generate:close()

--[=[
local function fmt_comment(comment)
   if comment:sub(1, 2) ~= '--' then
      comment = '-- ' .. comment
   end
   comment = comment:gsub('\n', '\n-- ')
   comment = comment:gsub(' +', ' ')

   if comment == '-- ' then
      comment = ''
   end

   return comment
end

local types = {
   ["void"]     = function() return 'void' end,
   ["char"]     = function() return 'char' end,
   ["float"]    = function() return 'float32' end,
   ["double"]   = function() return 'float64' end,
   ["*"]        = function(t) return 'pointer(' .. t .. ')' end,
   ['unsigned'] = function(t)
      return 'u'
   end,
   ['int']      = function(t) return 'int' end,
   ['[n]']      = function(t, n) return 'array(' .. t .. ', ' .. n .. ')' end,
   ['bool']     = function() return 'boolean' end,
}

local function c_type(t)
   local _type = ''

   for i = 1, #t do
      --print('t[i]: ', i, t[i])

      local ti = t[i]

      local as_number = tonumber(ti)
      if as_number then
         as_number = math.tointeger(as_number)
         ti = '[n]'
      end

      local types_ti = types[ti]

      local i_type = types_ti and types_ti(_type or '', as_number) or ti
      --print('i_type ' .. tostring(i) .. ' ' .. i_type)


      --print('end/i_type ' .. tostring(i) .. ' ' .. i_type)
      _type = i_type

      if i_type == 'char' or i_type == 'uchar' or i_type == 'int'
      or i_type == 'uint' or i_type == 'size' or i_type == 'long'
      or i_type == 'short' or i_type == 'ushort' then
         _type = 'c' .. _type
      end

      --print('type_i ' .. tostring(i) .. ' ' .. _type .. '\n')
   end

   --print('_type ' .. _type)

   return _type
end

local function generate_type(t)
   local type_result = c_type(t)

   if type_result == 'pointer(cchar)' then
      type_result = 'cstring'
   elseif type_result == 'pointer(void)' then
      type_result = 'pointer'
   end

   return type_result
end

local function generate_record(struct)
   local new_record = {
      fmt_comment(struct.comment),
      '\nglobal',
      struct.name,
      "<cimport, nodecl>",
      "=",
      "@record{\n",
   }

   for i = 1, #struct.members do
      local member = struct.members[i]
      table.insert(
         new_record,
         table.concat({
            subindent .. fmt_comment(member.comment),
            (member.comment ~= '' and '\n' .. indent or '') .. member.name,
            ': ',
            struct.name ~= 'Color' and generate_type(member.type) or 'uint8',
            ',',
            '\n'
         })
      )
   end

   new_record[#new_record] = new_record[#new_record] .. '}\n'

   return new_record
end

local function generate_alias(alias)
   return {'global', alias.name .. ':', 'type', '=', '@' .. alias.from, '\n'}
end

local function generate_enum(enum)
   local new_enum = {
      fmt_comment(enum.comment),
      '\nglobal',
      enum.name,
      '=',
      '@enum {\n'
   }

   local last_was_comment = false
   for i = 1, #enum.members do
      local member = enum.members[i]
      local m_value = member.value
      local v_or_1st = member.value or i == 1
      local underline_pos = member.name:find'_'

      table.insert(
         new_enum,
         table.concat({
            (v_or_1st and '' or (last_was_comment and '\n' or '')),
            ((v_or_1st) and subindent or (last_was_comment and indent or subindent)) .. fmt_comment(member.comment),
            ((member.comment ~= '' and m_value) and '\n' .. indent or '') .. member.name,
            m_value and ' = ' or '',
            (m_value and math.tointeger(m_value) or '') .. (m_value and ',' or ''),
            '\n'
         })
      )

      last_was_comment = v_or_1st
   end

   new_enum[#new_enum] = new_enum[#new_enum] .. '}\n'

   return new_enum
end

local function generate_RLAPI(RLAPI)
   local new_RLAPI = {
      '\n' .. fmt_comment(RLAPI.comment),
      '\nfunction' ,
      'Raylib.' .. RLAPI.name .. '('
   }

   for i = 1, #RLAPI.args do
      local _arg = RLAPI.args[i]
      _arg.name = _arg.name ~= 'end' and _arg.name or '_end'
      _arg.name = _arg.name ~= 'DOTDOTDOT' and _arg.name or '...'

      table.insert(
         new_RLAPI,
         table.concat({
            _arg.name,
            _arg.name ~= '...' and ': ' or '',
            generate_type(_arg.type),
            i <  #RLAPI.args and ',' or ''
         })
      )
   end

   table.insert(new_RLAPI, '): ')
   table.insert(new_RLAPI, generate_type(RLAPI.return_type))
   table.insert(new_RLAPI, '<cimport')
   table.insert(new_RLAPI, "'" .. RLAPI.name .. "', nodecl> end")

   return new_RLAPI
end

-- "global TraceLogCallback: type = function(logType: cint, text: cstring, args: va_list)",

local function generate_callback(callback)
   local new_callback = {
      fmt_comment(callback.comment),
      '\nglobal',
      callback.name .. ':',
      'type',
      '=',
      '@function('
   }

   for i = 1, #callback.args do
      local _arg = callback.args[i]

      table.insert(
         new_callback,
         table.concat({
            generate_type(_arg.type),
            i <  #callback.args and ',' or ''
         })
      )
   end

   table.insert(new_callback, ')')

   return new_callback
end

-- this is specific for Color constants
local function generate_define(define)
   return {
      'global',
      define.name .. ':',
      'Color',
      '<cimport, nodecl>'
   }
end

local generated_lines = {
   "--[[ This Source Code Form is subject to the terms of the Mozilla Public",
   "     License, v. 2.0. If a copy of the MPL was not distributed with this",
   "     file, You can obtain one at https://mozilla.org/MPL/2.0/. ]]",
   "",
   "-- Raylib and Raymath 3.0 wrapper",
   "-- based on raylib.h (https://github.com/raysan5/raylib/blob/3.0.0/src/raylib.h)",
   "-- and raymath.h (https://github.com/raysan5/raylib/blob/3.0.0/src/raymath.h)",
   "",
   "## linklib 'raylib'",
   "## linklib 'GL'",
   "## linklib 'glfw'",
   "## linklib 'openal'",
   "## linklib 'm'",
   "## linklib 'pthread'",
   "## linklib 'dl'",
   "## linklib 'X11'",
   "## linklib 'Xrandr'",
   "## linklib 'Xinerama'",
   "## linklib 'Xi'",
   "## linklib 'Xxf86vm'",
   "## linklib 'Xcursor'",
   "",
   "## cinclude '<raylib.h>'",
   "## cinclude '<raymath.h>'",
   "",
   "global Raymath = @record{}",
   "global Raylib  = @record{}",
   "",
   "local va_list <cimport, nodecl> = @record{}",
}

for i = 1, #raylib_table.callbacks do
   local callback = raylib_table.callbacks[i]
   local generated_line = table.concat(generate_callback(callback), ' ')
   table.insert(generated_lines, generated_line)
end

table.insert(generated_lines, "")

for i = 1, #raylib_table.enums do
   local enum = raylib_table.enums[i]
   local generated_line = table.concat(generate_enum(enum), ' ')
   table.insert(generated_lines, generated_line)
end

table.insert(generated_lines, "")

for i = 1, #raylib_table.structs do
   local struct = raylib_table.structs[i]
   local generated_line = table.concat(generate_record(struct), ' ')
   table.insert(generated_lines, generated_line)


   for j = 1, #raylib_table.aliases do
      local alias = raylib_table.aliases[j]

      if alias.from == struct.name then
         local generated_alias = generate_alias(alias)
         local generated_line = table.concat(generated_alias, ' ')
         table.insert(generated_lines, generated_line)
      end
   end
end

table.insert(generated_lines, "")

for i = 1, #raylib_table.RLAPIs do
   local RLAPI = raylib_table.RLAPIs[i]
   local generated_line = table.concat(generate_RLAPI(RLAPI), ' ')
   table.insert(generated_lines, generated_line)
end

table.insert(generated_lines, "")

for i = 1, #raylib_table.defines do
   local define = raylib_table.defines[i]
   local generated_line = table.concat(generate_define(define), ' ')
   table.insert(generated_lines, generated_line)
end

table.insert(generated_lines, " ")

local result = table.concat(generated_lines, '\n')

local file_to_generate = io.open('raylib.nelua', 'w+')
file_to_generate:write(result)
file_to_generate:close()
--]=]
