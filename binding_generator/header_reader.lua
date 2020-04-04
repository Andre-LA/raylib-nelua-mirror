-- this is a basic c header reader, it just implement sufficient
-- features to read the raylib.h and generates a table contaiing
-- enough information.

-- it's a experimental thing

local ins = require'inspect'

local function table_union(t1, t2)
   local r = {}
   for i=1, #t1 do r[#r+1] = t1[i] end
   for i=1, #t2 do r[#r+1] = t2[i] end
   for k, v in pairs(t1) do r[k] = v end
   for k, v in pairs(t2) do r[k] = v end
   return r
end

local function table_clone(t1)
   local r = {}
   for i=1, #t1 do r[#r+1] = t1[i] end
   for k, v in pairs(t1) do r[k] = v end
   return r
end

local function split(line)
   local split_line = {}
   for cap in line:gmatch'[%w%*%/]+' do
      table.insert(split_line, cap)
   end
   return split_line
end

local function join(split_line, words_count, start)
   local t = {}
   start = start or 0
   for i = start, words_count or #split_line do
      table.insert(t, split_line[i])
   end
   return table.concat(t, ' ')
end

local function detach_comment(split_line)
   local start = -1
   local comment_tbl = {}
   local comment;
   local new_split_line = {}

   for i = 1, #split_line do
      if start < 0 then
         if split_line[i] == '//' then
            start = i
         end
      else
         table.insert(comment_tbl, split_line[i])
      end
   end

   if #comment_tbl == 0 then
      return split_line
   else
      comment = table.concat(comment_tbl, ' ')
      for i = 1, start-1 do
         new_split_line[i] = split_line[i]
      end
   end

   return new_split_line, comment
end

local ignored_defines = {
   'RAYLIB_H',
}

local primitive_types = {
   ['void'] = true,
   ['int'] = true,
   ['char'] = true,
   ['*'] = true,
   ['float'] = true,
   ['double'] = true,
   ['bool'] = true,
}

local qualifiers = {
   ['const'] = true,
   ['unsigned'] = true,
}

local RLAPIs = {}
local structs = {}
local enums = {}

local function find_name(tbl, name)
   for i = 1, #tbl do
      if tbl[i].name == name then
         return i
      end
   end
   return nil
end

local function RLAPI_line(split_line)
   local RLAPI = {
      return_type = {},
      name = '',
      args = {},
      comment = ''
   }

   local function add_rlapi_arg()
      table.insert(RLAPI.args, {type = {}, name = ''})
   end

   table.remove(split_line, 1) -- remove 'RLAPI'

   local uncomment_split_line, comment = detach_comment(split_line)
   RLAPI.comment = comment

   print ('UN RLAPI: ' .. ins(uncomment_split_line))

   local s = 1

   -- collect RLAPI return types
   for i = s, #uncomment_split_line do
      local word = uncomment_split_line[i]

      local is_prim_type = primitive_types[word]
      local is_qualifier = qualifiers[word]
      local is_known_struct = find_name(structs, word)

      if is_prim_type or is_qualifier or is_known_struct then
         table.insert(RLAPI.return_type, word)
      else
         s = i
         break
      end
   end

   -- collect RLAPI name
   RLAPI.name = uncomment_split_line[s]
   s = s + 1

   -- collect RLAPI arguments
   add_rlapi_arg()

   for i = s, #uncomment_split_line do
      local word = uncomment_split_line[i]

      local is_prim_type = primitive_types[word]
      local is_qualifier = qualifiers[word]
      local is_known_struct = find_name(structs, word)

      if is_prim_type or is_qualifier or is_known_struct then
         table.insert(RLAPI.args[#RLAPI.args].type, word)
      else
         RLAPI.args[#RLAPI.args].name = word
         add_rlapi_arg()
      end
   end

   table.remove(RLAPI.args)

   print('RLAPI added to RLAPIs: ' .. ins(RLAPI))

   table.insert(RLAPIs, RLAPI)
end

local function struct_typedef_line(split_line, prev_comments)
   local struct = {
      name = '',
      members = {},
      comment = ''
   }

   struct.name = split_line[3]
   if prev_comments then
      struct.comment = table.concat(prev_comments, '\n')
   end

   print('struct added to structs: ' .. ins(struct))

   table.insert(structs, struct)
end

local function struct_member_line(split_line)
   local last_struct = structs[#structs]

   local function new_struct_member(_name, _type, _comment)
      return {
         name = _name or '',
         type = _type and table_clone(_type) or {},
         comment = _comment or {},
      }
   end

   local uncomment_split_line, comment = detach_comment(split_line)

   print('add struct member: ', ins(uncomment_split_line))

   local member_type = {}
   local members_name = {}

   for i = 1, #uncomment_split_line do
      local word = uncomment_split_line[i]

      local is_prim_type = primitive_types[word]
      local is_qualifier = qualifiers[word]
      local is_known_struct = find_name(structs, word)

      if is_prim_type or is_qualifier or is_known_struct then
         table.insert(member_type, word)
      else
         table.insert(members_name, word)
      end
   end

   for i = 1, #members_name do
      local member = new_struct_member(members_name[i], member_type, comment)
      print('struct member added: ' .. ins(member))
      table.insert(last_struct.members, member)
   end
end

-- main:
local state = 'neutral' -- can be
local raylib_h = io.open'raylib.h'

local comments_split_lines = {}
local line_number =  0

for line in raylib_h:lines() do
   line_number = line_number + 1

   -- separate * so the split function will split it as different words
   local line = line:gsub('%*', '* ')

   -- split the line
   local split_line = split(line)

   -- if the line have contents and it's after 123th line
   if #split_line > 0 and line_number > 171 then
      if state == 'neutral' then
         -- if the line start with a "RLAPI"
         if split_line[1] == 'RLAPI' then
            RLAPI_line(split_line)
         elseif split_line[1] == '//' then
            local _, comment = detach_comment(split_line)
            if comment then
               table.insert(comments_split_lines, line:sub(3))
            end
         elseif join(split_line, 2) == 'typedef struct' then
            if #split_line < 4 then
               state = 'typedef struct'
            end
            struct_typedef_line(split_line, comments_split_lines)
            comments_split_lines = {}
         end
      elseif state == 'typedef struct' then
         print(ins(split_line))

         -- if struct declaration ends
         if split_line[1] == (structs[#structs]).name then
            print('"typedef struct" state ends: ' .. ins(structs[#structs]))
            state = 'neutral'
         else
            struct_member_line(split_line)
         end
      end
   end
end

print'result:'
print(ins{structs, RLAPIs})

raylib_h:close()