;;; pygmy-mode.el --- major mode for Forth pseudo block files

;; Copyright 2017 Frank Sergeant

;; Version: 17.10
;; Author: Frank Sergeant <frank@pygmy.utoh.org>
;; Maintainer: Frank Sergeant
;; URL: http://pygmy.utoh.org
;; First release: October 2017
;; License: GNU General Public License 2
;; Distribution: This file is not part of Emacs

;;; Commentary:

;;; pygmy-mode.el is free software distributed under the terms of the
;;; GNU General Public License, version 2.  For details, see the file
;;; gpl-2.0.txt.

;;; For help with this mode, see the comment below in the definition
;;; of pygmy-mode or, start pygmy mode with
;;;
;;;    M-x pygmy-mode
;;;
;;; then press
;;;
;;;    C-h m


;;; Code:

;;; To do:
;;;    open a Pygmy Forth process and communicate with it using comint.


(require 'org)

;;---- VARS --------------------------------------------------------------------

(defvar pygmy-mode-map
   (let ((map (make-sparse-keymap)))
     (define-key map "\C-v" 'forward-block-narrow)
     (define-key map "\M-v" 'backward-block-narrow)
     (define-key map [next] 'forward-block-narrow)
     (define-key map [prior]  'backward-block-narrow)
     (define-key map [backtab]  'pygmy-global-cycle)
     (define-key map [tab]      'org-cycle)
     (define-key map (kbd "M-<up>")    'outline-move-subtree-up)
     (define-key map (kbd "M-<down>")  'outline-move-subtree-down)
     map)
   "Keymap for `pygmy-mode'.")

(defvar pygmy-font-lock-keywords
  '((":\\|;\\|VARIABLE" . font-lock-function-name-face)
    ("TRUE\\|FALSE" . font-lock-constant-face))
  "This is not used at this time.")

(defvar pygmy-outline-regexp "( +\\(block\\|shado\\)"
  "Regexp for identifying a heading and its level.

   A Forth block must start with a left parenthesis at the
   beginning of the line, followed by one or more spaces,
   followed by either 'block' or 'shado'.  The 'w' is chopped off
   to make source and shadow blocks the same level.  This can be
   adjusted by inserting additional spaces after the opening
   parenthesis.

   If this is changed, pygmy-heading-" )

(defvar any-block-regexp pygmy-outline-regexp)
(defvar source-block-regexp  "( +\\(block\\) ")
(defvar shadow-block-regexp  "( +\\(shadow\\) ")

;; (defvar pygmy-block-number-regexp
;;   (concat pygmy-outline-regexp " +\\([[:digit:]]+\\)"))

(defvar pygmy-block-number-regexp
  "^( +\\(block\\|shadow\\) +\\([[:digit:]]+\\)")

(defvar pygmy-comment-start "( ")
(defvar pygmy-comment-end   ")")

(defvar pygmy-first-cycle :true
  "Used by pygmy-global-cycle to decide whether to go to beginning of buffer.")


;;---- FUNCTIONS --------------------------------------------------------------------

(defun pygmy-outline-level ()
  "Adjust outline level so the top level is 1 instead of the length of the shortest heading.
   Using the default outline-level function with
   pygmy-outline-regexp, the top level would be 7 or so. Change
   this if necessary if pygmy-outline-regexp is changed."
  (- (outline-level) 6))

(defun start-of-block-p () 
  "Answer whether point is at the start of a block marker."
  (interactive)
  (looking-at any-block-regexp))

(defun start-of-shadow-block-p () 
  "Answer whether point is at the start of a shadow block."
  (interactive)
  (looking-at shadow-block-regexp))

(defun start-of-source-block-p () 
  "Answer whether point is at the start of a source block."
  (interactive)
  (looking-at source-block-regexp))

(defun forward-block-narrow ()
  "Move forward to start of next block and narrow the region to
   that block."
  (interactive)
  (widen)
  (outline-next-heading)
  (outline-show-subtree)
  (org-narrow-to-subtree)
  (setq pygmy-first-cycle :true))

(defun backward-block-narrow ()
  "Move backward to start of previous block and narrow the region to that block."
  (interactive)
  (widen)
  (ignore-errors 
    (outline-previous-heading))
  (unless (start-of-block-p)
    (widen)
    ;;(org-cycle t)
    (outline-next-heading))
  (outline-show-subtree)
  (org-narrow-to-subtree)
  (setq pygmy-first-cycle :true))

(defun pygmy-global-cycle (&optional arg)
  "When pygmy-first-cycle, run (org-cycle t), else run (org-global-cycle)."
  (interactive "P")
  (widen)
  (if pygmy-first-cycle
      (progn
        (org-cycle t)
        (beginning-of-buffer)
        (setq pygmy-first-cycle nil))
    (org-global-cycle)))
  
(defun start-of-block-p () 
  "Answer whether point is at the start of a block marker."
  (interactive)
  (looking-at outline-regexp))

(defun beginning-of-block ()
  "Move to the beginning of the current block"
  (interactive)
  (end-of-line)   ; move out of block marker if we are in one
  (re-search-backward outline-regexp nil 'end))

(defun current-block-number ()
  "Answer the block number of the current block.  This is taken
   from the block header, so it is a 'logical' block number
   rather than a count of physical blocks."
   (interactive)
   (save-excursion
     (beginning-of-block)
      (when (start-of-block-p)
           (progn
             (re-search-forward pygmy-block-number-regexp)
             (string-to-number (match-string-no-properties 2))))))

(defun renumber-blocks ()
  "Run through all the blocks, renumbering the blocks.  Renumber
   any shadow block the same as its preceding source block.
   Start with the number in the first block, which must be a
   source block."
  (interactive)
  (save-excursion
    (save-restriction   ;; do we really wish to later restore any narrowed state?
      (widen)           ;; or maybe we should *not* widen and thus allow renumbering a (narrowed) region
      (beginning-of-buffer)
      (when (not (start-of-block-p))  ;; when not at first block,
        (outline-next-heading))       ;;  go forward to the first block or end of buffer
      (if (start-of-shadow-block-p)
          (message "Shadow block cannot be the first block.")
        (when (start-of-block-p)         
          (let ((blk-num (current-block-number)))
            (end-of-line)  ;; so we don't renumber the very first block
            (while (re-search-forward pygmy-block-number-regexp nil t)
              ;;(message "%s %s" (match-string 1) (match-string 2))
              (save-match-data   ;; why do we need this? Ah, because current-block-number can change it
                (beginning-of-line)
                (when (start-of-source-block-p)
                  (setq blk-num (1+ blk-num)))) ; it's a source block, so bump blk-num
              (replace-match (number-to-string blk-num) t t nil 2)
              (end-of-line))))))))

;;;###autoload
(define-derived-mode pygmy-mode outline-mode "Pygmy"
  "Major mode for editing Forth pseudo block files.

This mode accompanies Pygmy Forth, available at http://pygmy.utoh.org.

This mode helps you edit a text file almost as if it were a
traditional Forth block file.  The trick is to mark the beginning
of each logical block with a special comment.  The opening
parenthesis must start at the begininng of a line, be followed by
one or more spaces, followed by either the word `block' or the
word `shadow', followed by at least one space or a closing
parenthesis.  The comment must be contained on a single line.  As
a Forth comment, it must end eventually with a closing
parenthesis.

Here are some examples:

( block 1   ------------------  load block)
( shadow 1 )
( block 2  miscellaneous)
(   shadow 2 miscellaneous )

The block numbers do not need to be consecutive, but they should
be monotonically increasing.  If not, run the command 

       M-x renumber-blocks.  

Shadow blocks are not essential but, if they
are used, should follow their associated source blocks.

The number of spaces between the opening parenthesis and `block'
or `shadow' determines the outline level of the heading.  This
allows you to nest shadow blocks under their source blocks if you
wish, e.g.,

( block 1   ------------------  load block)
(  shadow 1 )
( block 2  miscellaneous)
(  shadow 2 miscellaneous )
( block 3  something else)
(  shadow 3 something else )

or to nest a group of blocks under another block (perhaps a load
block), e.g.,

( block 1   Logic load block)
(  block2     Operators)
(  block3     Truth values)
( block 4   Some other category)
(  block 5    This)
(  block 6    That)
(  block 7    The other)

Put this file (pygmy-mode.el) somewhere in your Emacs load path
or put the full path to pygmy-mode.el in the autoload form shown
below.

Put something like the following in your .emacs file so that
files ending in .scr or .blk (for example) will be opened in
pygmy mode.  The following assumes pygmy.el is in your home
directory.

   (autoload
       \\='pygmy-mode
       \"~/pygmy-mode.el\"
     \"A major mode for editing Forth pseudo block files.\" t)

   (add-to-list \\='auto-mode-alist \\='(\"\\\\.scr\\\\\\='\" . pygmy-mode))
   (add-to-list \\='auto-mode-alist \\='(\"\\\\.blk\\\\\\='\" . pygmy-mode))

The available commands are:

C-v (forward-block-narrow) and M-v (backward-block-narrow) 
(or the page-up and page-down keys) 
   move forward or backward a single block.

renumber-blocks 
   renumber the blocks consecutively, starting with the block
   number of the first block in the file.  Each shadow block is
   given the same number as its preceding source block.

<tab> (org-cycle)
  When on a heading (the block comment line), cycle the
  visibility of the current subtree.

<backtab> (pygmy-global-cycle)
  Cycle outline visibility of the entire file through the 3
  states: just major headings, all headings, and everything.

M-<down> (outline-move-subtree-down)  
  Move current subtree down

M-<up> (outline-move-subtree-up)
  Move current subtree up

Other commands:
\\{pygmy-mode-map}
"
   (setq-local comment-start pygmy-comment-start)
   (setq-local comment-end pygmy-comment-end)
   (setq-local outline-regexp pygmy-outline-regexp)
   (setq-local org-outline-regexp pygmy-outline-regexp)
   (setq-local outline-level 'pygmy-outline-level))

(provide 'pygmy-mode)

;;; pygmy-mode.el ends here
