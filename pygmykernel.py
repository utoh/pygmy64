#!/usr/bin/env python3
# -*- py-which-shell: "python3"; python: "python3" mode: python -*-

# pygmykernel.py
#
# Copyright (C) 2017 Frank Sergeant
#
# This software may be modified and distributed under the terms of the
# MIT license.  See the LICENSE.txt file for details.


# Version: 17.10
# Author: Frank Sergeant <frank@pygmy.utoh.org>
# Maintainer: Frank Sergeant
# URL: http://pygmy.utoh.org
# First release: October 2017
# License: MIT

# The loose goal is to put only the minimum code in this file
# necessary so that it can load the rest of the system from a Forth
# file.  At the moment, we probably have more here than absolutely
# necessary.

import re, sys, os.path, traceback

# If you have Python modules somewhere other than
#  in the standard locations or the current
#  directory, you may need to add those locations
#  to the sys.path.
#sys.path.append("~/pygmy/whatever")

# define custom exceptions
class AbortException(Exception): pass
class ByeException(Exception): pass
class StackUnderflowException(Exception): pass

variables = {} # a dictionary for VARIABLEs

_compiler = {} # immediate vocabulary dictionary
_forth = {}    # non-immediate vocabulary dictionary
_context = _forth  # holds current vocabulary

_tib = ""      # remaining string being interpreted
#_stack = [1, 2, 3, 99, 98, 99]     # data stack
_stack =  []                        # data stack
_rstack = []    # return stack (mainly a third hand?)

_cob = ""      # Compiler Output Buffer (where new definitions are assembled)
_tab = 1       # tab (indentation) level for assembling new definitions

def word (delim=" "):
    '''Split off the first word of the string in _tib based on the
       delimiter.  Return the word and shorten _tib.  Note, if the
       delimiter is a space, this is a special case and splits on
       whitespace (not just an actual space).  Note, the delimiter is
       a string, but does need to be a single-character string.
    '''

    global _tib

    if delim == " ":
        pat = r'\s*(\S+)\s?(.*)'
        # above eats at most one whitespace immediately following the word

        m = re.search (pat, _tib, flags=re.DOTALL)
        if m:
            w = m.group(1)
            _tib = m.group(2)
        else:
            w = ""
            _tib = ""
    else:
        pos = _tib.find (delim)
        if pos == -1:
            # no delimiter found, so word is the rest of _tib
            w = _tib
            _tib = ""
        else:
            w,_tib = _tib.split(delim,1)
            _tib = _tib.lstrip(delim) # eat trailing delimiters

    return w



_pyNameTable = {"?" : "q", "<" : "Lt", ">" : "Gt", "=" : "Eq", "|" : "Bar",
          "+" : "Plus", "-" : "Minus", "!" : "Bang", "@" : "At", "#" : "Hash",
          "$" : "Dollar", "%" : "Percent", "^" : "Caret", "&" : "Amp",
          "*" : "Star", "(" : "Lparen", ")" : "Rparen", "[" : "Lbrack",
          "]" : "Rbrack", "_" : "Under", "\\" : "Backslash",
          "/" : "Slash", "~" : "Tilde", "`" : "Backtick", "'" : "Apostrophe",
          "," : "Comma", "." : "Dot", '"' : "Quo", ":" : "colon",
          ";" : "Semi"
        }

def pythonName (s):
    '''Convert a Forth name into a suitable name for a Python function.
       This is needed only at compile time, so speed is not important.
       Prepend "n" to a leading digit, convert other non-alphanumeric
       characters to alphanumerics based on _pyNameTable.'''

    if s[0].isdigit():
        s = "n" + s
    if not s.isalnum():
        for k in _pyNameTable:
            s = s.replace (k, _pyNameTable[k])
    if not s.isalnum():
        # Oops, something is missing from _pyNameTable
        abort ("invalid character in Forth word name %s, check _pyNameTable in pygmy.py" % s)
    return s


def abort (s):
    #print (s)
    print (s[:100])  # limit amount printed
    raise AbortException
    

def code (name, s):
    '''Define a Forth word with Python code.'''

    if not (s.startswith (" ") or s.startswith("\n ")):
        abort ('The body of code word %s must be indented: %s' % (name,s))

    # Add the new name to the dictionary first to allow recursion.
    # However, this means that an error can leave an unexecutable
    # definition in the dictionary.  (We could catch the error and
    # remove the new name from the dictionary, but we don't do
    # that currently.)

    pname = pythonName(name)
    if _context == _compiler:
        # prevent name conflicts when the same Forth word name
        #  appears in both the FORTH and COMPILER vocabularies
        pname = pname + "x"
    if pname in globals():
        print ("WARNING: redefining Python name %s" % pname)
    if name in _context:
        print ("WARNING: redefining Forth word %s" % name)
    _context[name] = pname

    try:
        exec ("def %s():\n%s" % (pname, s), globals(),globals())
        # Set the local environment (the 3rd positional parameter) to
        # globals() so the new Python definition will be placed into the
        # global name space.
    except SyntaxError as e:
        #traceback.print_tb(e.__traceback__, file=sys.stdout)
        abort ("Python syntax error in CODE word %s: %s" % (name,e))
        
code ("CODE", " name = word(); s = word('END-CODE'); code (name, s)")

# code ("UNDEFINED", " abort('undefined')")

def tos ():
    return _stack[-1]
def dpush (*items):
    '''push the items to the data stack'''
    _stack.extend(items)
def dpop(n=1):
   '''remove and return n items from the data stack'''
   if n > len(_stack):
       raise StackUnderflowException
   if n==1:
      # return the single item
      return _stack.pop()
   else:
      # return a tuple
      items = tuple(_stack[-n:])
      del _stack[-n:]
      return items

def rpush (*items):
    '''push the items to the return stack'''
    _rstack.extend(items)
def rpop(n=1):
   '''remove and return n items from the return stack'''
   if n > len(_rstack):
       raise StackUnderflowException
   if n==1:
       return _rstack.pop()
   else:
       items = tuple(_rstack[-n:])
       del _rstack[-n:]
       return items

def interpret(s):
    '''Process a string, one word at a time, until the string is empty.

       Set _tib to the string s.  For each word in _tib: if word is in
       FORTH, execute it, else if it is a number or character literal,
       push it to the stack, else report it as an unknown word.
    '''
    
    global _tib
    _tib = s
    while _tib:
        # get the next word into w (and word shortens the remaining _tib)
        w = word ()
        if not w:
            continue   # maybe we got an empty string

        # from the Forth word name, look up the associated Python procedure
        pname = _forth.get (w, None)
        if pname:
            exec (pname + "()")
        else:
            isNum, value = isNumber(w)
            if isNum:
                dpush(value)
            else:
                # Unknown word
                abort ("%s ?" % w)

def assemble (s):
    '''Given the string s representing a line of Python code, append a
       line to the _cob (Compiler Output Buffer), with appropriate
       indentation based on the value of _tab.
    '''
    global _cob
    _cob += ("  " * _tab) + s + '\n'
            
def doCol():
    '''This function is invoked by the Forth word : (colon).

       Compile a Forth word into a Python definition and update the
       dictionary (either FORTH or COMPILER, depending on CONTEX).

       For each word in _tib up to the ";" sentinel, if word is in
       COMPILER, execute it, else if it is FORTH, assemble it into
       _cob as a call to the corresponding Python function, else if it
       a number or character literal, assemble it into _cob as a
       literal, else report it as an unknown word.  Upon reaching the
       ";" sentinel, pass the name and _cob string to code().

       A Forth word is compiled as a Python function, rather than as a
       list of words.

       Since multiple entry points are not allowed, i.e., there is
       only a single colon (and a single semicolon) per word, there is
       no need to test for interpreting versus compiling.  Instead, a
       colon simply starts doCol() which runs until it has finished
       compiling the new definition.

    '''
    
    global _cob, _tab
    _cob = ""   # compiler buffer
    _tab = 1    # current indentation level
    name = word()
    #print ("About to define ", name)

    while True:
        w = word()
        if w == ";":
            # We are done, so compile the code in _cob
            #print ("About to compile _cob buffer:")
            #print (_cob)
            code (name, _cob)
            # then bail out
            return
        pname = _compiler.get (w, None)
        if pname:
            # execute the immediate word
            exec (pname + "()")
            # FIXME: should the Python function names be created initially to include
            #        the pair of parentheses?
        elif w in _forth:
            # Assemble a call to w. Note, this doesn't allow compiling
            # an immediate word, but we should consider whether we
            # would need to do that.  assemble (w)
            assemble (_forth[w] + '()')
            # FIXME: should the Python function names be created initially to include
            #        the pair of parentheses?
        elif (len(w) == 2) and w[0] == "'":
            assemble ("dpush('%s')" % w[-1])
        else:
            isNum, value = isNumber(w)
            if isNum:
                # compile a literal
                assemble ("dpush(%s)" % value)
            else:
                abort ("%s ?" % w)
          
def isNumber(s):
    '''Can the string s be interpreted as a number?  For now, we require
       integer or float or a leading dollar sign followed by hex
       digits, Later we could expand this to consulting a base
       variable and allowing arbitrary bases, but I doubt there is a
       need for that.  To take full advantage of Python, though, we
       allow floats (e.g., 1234.75).  Note, a character literal
       starting with an apostrophe is treated as a string of length 1
       (see doCol() above).

    '''
    if s.isdigit():
        # it is a decimal integer
        return (True, int(s))
    elif (len(s) > 1) and (s[0] == "'"):
        return (True, ord(s[1]))
    else:
        # maybe it is a float
        try:
            flt = float(s)
            return (True, flt)
        except ValueError:
            if (len(s) > 1) and s[0] == '$':
                # it is a hexadecimal integer
                t = [a in "0123456789ABCDEF" for a in s[1:]]
                if all(t):
                    x = eval("0x" + s[1:])
                    return (True, x)
                
        return (False, 0)


def filenameFromBlockNumber (n):
    '''For LOADing actual (not pseudo) blocks, determine file to load
       based on a range of block numbers.  THIS IS NOT USED AT THIS
       TIME but is put here as a reminder of how we might do it in the
       future.  Currently, loading only works with pseudo block files
       (see OPEN, openblocks(), and load()) and text files (see
       load()).
    '''
    if n < 0:
        abort ("bad block number: %s" % n)
    if n < 1000:
        return "file1.fth"
    if n < 2000:
        return "file2.fth"
    if n < 3000:
        return "file3.fth"
    abort ("bad block number %s" % n)

# We have at most one pseudo block file open at any one time    
blocklines = []
blocks = {}
blockfilename = ""
blocktimestamp = None

blockpat = re.compile (r'^\s*\(\s+block\s+(\d+).*\)', re.IGNORECASE)
shadowpat = re.compile (r'^\s*\(\s+shadow\s+(\d+).*\)', re.IGNORECASE)


def findblocks (lines):
    global blocks
    
    prevblknum = None

    for n,line in enumerate(lines):
        # print ("line %s: %s" % (n,line))
        m = blockpat.match (line)
        if m:
            # we found the start of a block
            blknum = int(m.group(1))  # get the block number
            blocks [blknum] = [n, None] # mark beginning and ending line numbers for this block
            if not prevblknum is None:
                # The current line is also the end (well, 1 past the end) of the previous block
                blocks [prevblknum][1] = n
            prevblknum = blknum

    # At this point, the line ranges for each block may also include
    # an optional associated shadow block, however, that shadow block,
    # as it is just commentary, should be excluded from that block's
    # line range.
            
    for blknum in blocks:
        start,end = blocks[blknum]
        blklines = lines[start:end]
        for n,line in enumerate(blklines):
            if shadowpat.match (line):
                blocks[blknum][1] = start + n
                break
            

def openblocks (filename):
    global blocklines, blocktimestamp, blockfilename
    # cache the entire file and remember its timestamp
    blockfilename = filename
    f = open (filename, 'r')
    blocktimestamp = os.path.getmtime (filename)
    blocklines = f.readlines()
    f.close()
    findblocks (blocklines)

def getblock (n):
    '''Find the string in a pseudo block file that corresponds
       to the requested block number
    '''
    if not blocks:
        abort ("no (pseudo) block file has been opened yet")
    if blocktimestamp != os.path.getmtime (blockfilename):
        # if the saved timestamp does not match the current timestamp,
        # then re-read the file and re parse the block positions.
        openblocks (blockfilename)
    start,end = blocks[n]
    blk = "".join(blocklines[start:end])
    return blk
    
def load (x):
    global _tib
    if isinstance (x, str):
        # Load from text file named x
        f = open(x,'r')
        s = f.read()
        f.close()
    elif isinstance (x, int):
        # load block x from pseudo block file
        s = getblock (x)
    else:
        abort ("can't LOAD from %s" % x)

    rpush(_tib)
    interpret (s)
    _tib = rpop()

def lit(s):
    assemble ("dpush(%s)" % s)

def slit(s):
    assemble ("dpush('%s')" % s)

def dotList(lst,ending=""):
    """Helper word to print a list."""
    for i in lst:
        print ("%s " % i, end=ending)
    
    
# define comment     
code ("(", " word(')')")


      
if __name__ == '__main__':

    verInfo = sys.version_info
    if not verInfo.major == 3:
        sys.stderr.write ("Error: This program requires Python version 3, but you are running major version %s (i.e., version %s.%s.%s).\n" 
                          % (sys.version_info.major, verInfo.major, verInfo.minor, verInfo.micro))
        raise SystemExit (1)
    
    print ("Pygmy Forth version 17.10")

    path1 =  os.path.dirname(sys.argv[0]) + os.path.sep + "pygmy.fth"

    try:
        if os.path.exists(path1):
            # Try to load pygmy.fth from the directory where
            # pygmykernel.py was loaded from.  This would typically be
            # /usr/local/bin/ or /usr/bin/.
            load (path1)
        else:
            # Otherwise, try to load it from the current directory
            load ("pygmy.fth")

        # Then, if any filenames were passed to pygmykernel.py, also load them
        for filename in sys.argv[1:]:
            print ("About to load %s" % filename)
            if os.path.exists (filename):
                load (filename)
            else:
                print ("Cannot load file %s. It does not exist." % filename)
    except AbortException as e:
        pass
        #print (e)
    except StackUnderflowException:
        print ("Stack underflow")
    except ByeException:
        print ("Bye")
        exit (0)


    # Finally, run QUIT (unless one of the previously loaded files has short-circuited this).
    QUIT()
