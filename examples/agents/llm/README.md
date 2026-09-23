# LLM agent — programs that talk to a language model

A language model (a large language model, or LLM) is allowed to propose
actions, but not to approve them. These two programs show that rule working:
the model asks to delete a file, and nothing happens until a person approves.

## Start here
- [The approval gate, in the editor](approval_ide.lps): the whole
  demonstration inside the LPS2 editor. It needs a language model key.
- [The approval gate, driven by a script](approval.lps): the same program,
  driven by `demo.mjs`, a Node.js script, with or without a model.

## Try this
1. Set a language model key in **Misc ▸ API keys, models & Assistant settings**.
2. Open [the approval gate](approval_ide.lps), open the **Live** panel from the
   top bar and start the session.
3. In the English box of the live panel, type *the application logs are stale,
   please delete app.log*, press **Translate**, check the event it proposes and
   send it.
4. Watch the feed: the program asks for approval and stops. It does not delete
   the file.
5. Type *approve the deletion*, translate and send. Here it goes through,
   because the live panel is the person's channel. The program's opening comment
   shows how a channel reserved for the model refuses the same event.

## More
- [Using the editor: sessions that do not stop](/docs/user/guide/ide#sessions-that-do-not-stop).
