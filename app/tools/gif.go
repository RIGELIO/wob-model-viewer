// Copyright 2026 RIGELIO Studio. SPDX-License-Identifier: MIT
package main

import (
	"bytes"
	"errors"
	"fmt"
	"image"
	"image/color/palette"
	"image/draw"
	"image/gif"
	"image/png"
	"math"
	"os"
	"path/filepath"
	"strconv"
)

func encodeGIF(dir string, fps int, output string) error {
	paths, err := filepath.Glob(filepath.Join(dir, "frame-*.png"))
	if err != nil || fps < 5 || fps > 30 || len(paths) < 1 || len(paths) > 240 {
		return errors.New("invalid GIF range or frame rate")
	}
	result := &gif.GIF{LoopCount: 0}
	width, height := 0, 0
	for index, path := range paths {
		imageData, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		config, err := png.DecodeConfig(bytes.NewReader(imageData))
		if err != nil || config.Width < 1 || config.Width > 1280 || config.Height < 1 || config.Height > 720 {
			return errors.New("invalid GIF frame size")
		}
		if index == 0 {
			width, height = config.Width, config.Height
		}
		if config.Width != width || config.Height != height {
			return errors.New("all GIF frames must have the same dimensions")
		}
		frame, err := png.Decode(bytes.NewReader(imageData))
		if err != nil {
			return err
		}
		paletted := image.NewPaletted(frame.Bounds(), palette.Plan9)
		draw.FloydSteinberg.Draw(paletted, frame.Bounds(), frame, image.Point{})
		result.Image = append(result.Image, paletted)
		end := int(math.Round(float64(index+1) * 100 / float64(fps)))
		start := int(math.Round(float64(index) * 100 / float64(fps)))
		result.Delay = append(result.Delay, end-start)
	}
	file, err := os.CreateTemp(filepath.Dir(output), ".wob-gif-*")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	err = gif.EncodeAll(file, result)
	closeErr := file.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(file.Name(), output)
}

func run(args []string) error {
	if len(args) != 3 {
		return errors.New("usage: wob-gif frame-directory fps file.gif")
	}
	fps, err := strconv.Atoi(args[1])
	if err != nil {
		return err
	}
	return encodeGIF(args[0], fps, args[2])
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
