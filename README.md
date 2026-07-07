# altpattern

this is a library that will let you use the pipe `|` alternator as a magic
character in lua's [native pattern matching functions][docs]. you can use it 
like this (maybe come up with a better example lol):
```lua
require("altpattern"):overload()

local s = io.read()
name = s:match("my name is (%w+)|i am called (%w+)")
if name ~= nil then
    print("hello "..name.."!")
end
```
and in most other ways you can imagine using it. by default you can always 
call the old functions using `string.rawmatch` or `("string"):rawmatch`. if 
you'd rather put these functions somewhere else, you can provide a table `t` 
as an argument to `overload` and it will instead put the old pattern 
matching functions in that table instead of renaming the ones in the global 
`string` table. obviously you can `local alt = require("altpattern")` or 
something too, and never bother with overloading

you can group alternations just fine, like with `(a|b)`. it is important to 
note that these groups are non-capturing. further, because of certain 
implementation details (my invincible sloth), i have not implemented 
captures within quantified alternated groups. trying to do that will throw 
an error. this is simply because the parens are non-capturing--any 
parenthetical expression with a top-level pipe alternator is compiled down 
into a pattern expression which excludes those parens. while the compiler 
knows to make the special case `(a|b)+` into `[ab]+`, there is no way to, 
using only lua patterns, match an expression like `(a|bc)+`. i have 
implemented functionality for this with a little parser that runs the 
pattern manually (more on this later), even if you ask it to alternate 
recursively, e.g., with `(a|(b|c))`. however, to process that expression, 
the compiler removes the parentheses; they do not work as a capture group. 
you can surround it in another set of parentheses, like `((a|bc)+)` to 
capture the full quantified match. what you really want to worry about is 
the kind of expression which includes a capture group inside the non-
capturing parentheses, like in `(a|(b)c)+`. this kind of expression will 
just throw an error. i dont really even know what the expected behavior of 
this kind of pattern would be. im not a regex genius. i do know that it 
likely would produce an arbitrary number of capture groups that is 
impossible to predict without the subject string. whatever string 
manipulation that you might be used to getting for free by capturing inside 
quantified alternated groups, you will have to do it manually or use
someone else's code

in all cases but the aforementioned alternated group with multi-character
members, this library will translate your pattern with pipe alternators into 
a list of patterns, all of which are run using the internal c engine against 
the subject string. in these typical cases, speed is not any more of an 
issue than in directly calling the standard library's pattern-matching 
functions. this is the more that i said would be later--recall that the 
library can compile `(a|b)+` into `[ab]+`, but there is no real way to use 
lua patterns to translate  `(a|bc)+` into pure match-patterns. when the 
atomizer (this is what i have called the function which translates single-
char alternative groups into character classes) realizes this, it gets 
really frustrated and asks the compiler to manually process the match in 
native lua. the in-lua pattern processing is avoided when possible because 
it increases the runtime per-call by like 3 or 4 orders of magnitude. i did 
what i could think of to try and reduce the size of the constant factor--
the compiled patterns are cached rather than re-checked for their need to 
manually iterate. the rest is up to your discretion. i hate to be the 
redditor who tells you that the the question you're asking is stupid and 
wrong--i love my favorite toy scripting language--but if you are looking for 
something faster, you should not really be writing your code in lua, and you 
should at least be using a real c binding for real regular expressions

> Unlike several other scripting languages, Lua does not use POSIX regular 
> expressions (regexp) for pattern matching. The main reason for this is 
> size: A typical implementation of POSIX regexp takes more than 4,000 
> lines of code. This is bigger than all Lua standard libraries together. 
> In comparison, the implementation of pattern matching in Lua has less 
> than 500 lines.[^1]

[^1]: https://www.lua.org/pil/20.1.html

so if nothing else you can take this as an argument for excluding the pipe 
alternator from lua's pattern syntax

[docs]: https://www.lua.org/manual/5.5/manual.html#6.5
