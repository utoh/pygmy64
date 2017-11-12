( pygmy.fth

  Copyright 2017 Frank Sergeant

  This software may be modified and distributed under the terms of the
  MIT license.  See the LICENSE.txt file for details.

  This file is part of Pygmy Forth, version 17.10

  Author: Frank Sergeant <frank@pygmy.utoh.org>
  Maintainer: Frank Sergeant
  URL: http://pygmy.utoh.org
  First release: October 2017
  License: MIT

  pygmy.fth is loaded by pygmykernel.py to complete the basic Pygmy
  Forth system.
 )


( *********  Useful for loading rest of this file ******** )
CODE .    print(dpop(),end=' ')  END-CODE
CODE CR   print()                END-CODE
CODE "    dpush(str(word('"')))  END-CODE

( " Starting" .  CR )


( *********  Math ******** )

CODE +    a,b = dpop(2); dpush(a+b)  END-CODE
CODE 1+     a = dpop();  dpush(a+1)  END-CODE
CODE -    a,b = dpop(2); dpush(a-b)  END-CODE
CODE *    a,b = dpop(2); dpush(a*b)  END-CODE
CODE /    a,b = dpop(2); dpush(a/b)  END-CODE

( " Math loaded" . CR )

( *********  Stack ******** )

CODE DROP  dpop()                      END-CODE
CODE DUP   dpush(tos())                END-CODE
CODE SWAP  a,b = dpop(2); dpush(b,a)   END-CODE
CODE OVER  a,b = dpop(2); dpush(a,b,a) END-CODE
CODE .S    dotList(_stack)             END-CODE
CODE .RS   dotList(_rstack)            END-CODE
CODE R@    dpush(_rstack[-1])          END-CODE
CODE PUSH  rpush(dpop())               END-CODE
CODE POP   dpush(rpop())               END-CODE

CODE 2DUP   a,b=dpop(2); dpush(a,b); dpush(a,b)  END-CODE
CODE 2DROP  dpop(2)                              END-CODE

( " Stack loaded" . CR )


( *********  Printing ******** )

CODE .H   print("%x" % dpop(),end=' ')  END-CODE


CODE EMIT
    # We may wish to change this to allow redirecting to a file
    x = dpop()
    if isinstance (x, str):
        #print(x, end='')
        print(x[:1], end='')
        # print at most the first character of the string
    else:
        print(chr(x), end='')
  END-CODE
 
( " Printing loaded" . CR )


( *********  Compiling and Interpreting ******** )

CODE COMPILER
    global _context
    _context = _compiler   END-CODE

CODE FORTH
    global _context
    _context = _forth    END-CODE

CODE WORDS
   for w in _context.keys():
       print ("%s " % w, end='')
  END-CODE

( " WORDS loaded" . CR )

( s - s #)
CODE COUNT  dpush(len (tos()))              END-CODE
CODE TYPE  s,n = dpop(2); print(s[:n],end=' ') END-CODE

CODE BL     dpush(' ')                     END-CODE
CODE WORD   w = word (dpop()); dpush(w)    END-CODE
CODE :      doCol()                        END-CODE
CODE BLOCK  n=dpop(); dpush(getblock(n))   END-CODE
CODE LOAD   x=dpop(); load(x)              END-CODE

CODE BYE    raise ByeException             END-CODE

( filename - )
CODE OPEN
     openblocks (dpop())
  END-CODE

CODE VARIABLE
    # usage:   VARIABLE <varname>
    #  e.g.,   VARIABLE STATUS
    w = word()
    variables[w] = 0
    code (w, " dpush('%s')" % w)
  END-CODE

( s -)
CODE ABORT  abort (dpop()) END-CODE

CODE QUIT
    global _rstack
    while True:
        try:
            _rstack = []   # re-initialize return stack, i.e. RP!
            s = input ("> ")
            interpret(s)
            print (" ok")
        except AbortException as e:
            pass
            #print (e)
        except StackUnderflowException:
            print ("Stack underflow")
        except ByeException:
            print ("Bye")
            exit (0)
        except Exception as e:
            print (e)
            traceback.print_stack()
            
 END-CODE

( " Compiling and Interpreting loaded" . CR )

( *********  Fetching and Storing ******** )

CODE @
   #  ( var - value)
   # a variable is a string key into the variables dictionary
   dpush(variables[dpop()])
  END-CODE

CODE !
   #  ( value var -)
   # a variable is a string key into the variables dictionary
   val,varname = dpop(2)
   variables[varname] = val
  END-CODE

: ?   @ .  ;


( *********  Logic  ******** )
(  these are logical, not bit-wise )

CODE TRUE   dpush(True)   END-CODE

CODE FALSE  dpush(False)  END-CODE

CODE AND
  a,b=dpop(2)
  # dpush(a and b)
  dpush(not( not(a and b)))
  END-CODE

CODE OR
  a,b=dpop(2)
  # dpush(a or b)
  dpush(not( not(a or b)))
  END-CODE

CODE NOT    a=dpop();    dpush(not a)    END-CODE

CODE XOR
  a,b = dpop(2)
  dpush (not (not ( (a and not b) or (b and not a) )))
  END-CODE


CODE ."   dpush(str(word('"'))); COUNT(); TYPE()  END-CODE


COMPILER     ( ################################ )


( *********  Compiling Strings ******** )

CODE "     slit(word('"'))   END-CODE


CODE ."    slit(word('"')); assemble ("COUNT(); TYPE()")  END-CODE


CODE (     word(')')         END-CODE

( *********  Control Flow ******** )

CODE ;;     assemble ("return()")   END-CODE
CODE EXIT   assemble ("return()")   END-CODE

CODE IF
  global _tab
  assemble ("if dpop():")
  _tab += 1
 END-CODE

CODE ELSE
  global _tab
  _tab -= 1
  assemble ("else:")
  _tab += 1
 END-CODE

CODE THEN
  global _tab
  _tab -= 1
 END-CODE

CODE BEGIN
  global _tab
  assemble ("rpush (0)")
  assemble ("while not rpop():")
  _tab += 1
 END-CODE

CODE UNTIL
  global _tab
  assemble ("rpush(dpop())")
  _tab -= 1
 END-CODE

CODE AGAIN
  global _tab
  assemble ("rpush(0)")
  _tab -= 1
 END-CODE

CODE WHILE
  global _tab
  assemble ("if not dpop():")
  assemble ("  rpush(-1)")
  assemble ("else:")
  assemble ("  rpush(0)")
  _tab += 1
 END-CODE

CODE REPEAT
  global _tab
  _tab -= 1
 END-CODE

CODE FOR
  global _tab
  assemble ("for I in range (dpop()-1,-1,-1):")
  _tab += 1
 END-CODE

CODE I
  assemble ("dpush(I)")
 END-CODE

CODE NEXT
  global _tab
  _tab -= 1
 END-CODE



FORTH     ( ################################ )

: THRU ( first last -)
  OVER - 1+ FOR DUP I + LOAD NEXT  DROP  ;

( *********  Comparison ******** )

CODE =   a,b = dpop(2); dpush(a == b)  END-CODE
CODE >   a,b = dpop(2); dpush(a > b)   END-CODE
CODE <   a,b = dpop(2); dpush(a < b)   END-CODE
CODE <=  a,b = dpop(2); dpush(a <= b)  END-CODE

: 0= ( n - f)  0 = ;


( *********  Start Interactive Loop ******** )

" Welcome to Pygmy Forth" .  CR

(  QUIT  )

