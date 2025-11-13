# Autocommit

Automatically `git add` and `git commit` with an AI generated commit message based on the diff.

Requires a local ollama installation to work. The IP in my script is set to my own local installation and will need to be changed on your system.

`start rant`

Tis was created because I use git to back up my writing directories. This was NOT intedded for actual code repositories!
The script will automatically generate a commit every 30 minutes (Interval can be adjusted with the `-i` option).

I wrote this for writing because Obsidian.md corrupted its final file! (No, it's not an addon doing the corruption. Yes, I'm a programmer and know how markdown files work. Yes, it's definately Obsidian that corrupts the files: No other text editing program does this, nor touches the corrupted files, and I've written sloppy text manipulation software myself that corrupts files like this in certain edge cases. It is definately Obsidian, despite what Internet people tell you. It's a problem inherent in any text editor that "automatically saves".)

I do like Obsidian, other than the file corruption thing and the lack of explicit saving, and there's really no other "writer's program" out there that's in useable shape. I've looked. I also always forgot to manually commit. So now I just run this when I work.

Moral of the story: Don't write your software to automatically save mysteriously behind the scenes! Make the user explicitly save! I can't believe this antipattern is so prolific these days.

`end rant`

## Files

`autocommit.sh` 

The first prototype in bash. Should work on a windows **git bash** shell terminal.

`main.go`

This is to be compiled as a standalone exe you can just run. It opens its own terminal.




## Build:

```sh
go mod init github.com/erickveil/autocommit
go build -o autocommit.exe
```


## Run:

```sh
# Basic Run
./autocommit.exe

# Verbose
./autocommit.exe -v

# Change the commit interval (in minutes)
./autocommit.exe -i 15
```

