# Autocommit

Automatically `git add` and `git commit` with an AI generated commit message based on the diff.

Requires a local ollama installation to work. The IP in my script is set to my own local installation and will need to be changed on your system.

Tis was created because I use git to back up my writing directories. This was NOT intedded for actual code repositories!
The script will automatically generate a commit every 30 minutes (Interval can be adjusted with the `-i` option).

I wrote this for writing because sometimes my files get corrupted.


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

