package main

import (
	"fmt"
	"os"
)

const Version = "0.1.0"

func main() {
	if len(os.Args) < 2 {
		fmt.Println("ChengetAI Deploy")
		fmt.Println("")
		fmt.Println("Usage:")
		fmt.Println("  chengetai version")
		fmt.Println("  chengetai deploy dspace")
		fmt.Println("  chengetai deploy koha")
		fmt.Println("  chengetai deploy campus")
		return
	}

	switch os.Args[1] {

	case "version":
		fmt.Println("ChengetAI Deploy v" + Version)

	case "deploy":

		if len(os.Args) < 3 {
			fmt.Println("Please specify a deployment target.")
			return
		}

		switch os.Args[2] {

		case "dspace":
			fmt.Println("🚀 Deploying DSpace 10...")

		case "koha":
			fmt.Println("🚀 Deploying Koha...")

		case "campus":
			fmt.Println("🚀 Deploying Complete Digital Campus...")

		default:
			fmt.Println("Unknown deployment target:", os.Args[2])
		}

	default:
		fmt.Println("Unknown command.")
	}
}
