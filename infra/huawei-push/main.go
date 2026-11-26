package main

import (
	"fmt"
	"log"
	"os"
)

func main() {
	if len(os.Args) != 2 || os.Args[1] != "serve" {
		fmt.Fprintln(os.Stderr, "Usage: huawei-push serve")
		os.Exit(2)
	}
	if err := runHostedPush(); err != nil {
		log.Fatal(err)
	}
}
