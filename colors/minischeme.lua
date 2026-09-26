-- "Blue-yellow" color scheme
--
-- Palettes are mostly hand crafted leveraging OKLch color space.
-- Hues are chosen to look pretty while being far enough from one another.
--
-- Bg and Fg sets are computed with `require('mini.hues').make_palette()`.
--
-- Rainbow colors aim to have the same L and c, with varying h.
-- Initial hex colors are computed with 'mini.colors' and `gamut_clip='cusp'`.
-- Then possibly further tweaked to have better usability.
-- Background colors are meant to be visible and distinctive.

local palette

--stylua: ignore
if vim.o.background == 'dark' then
  palette = {
    -- Main background: L=10, c=3, h=240
    bg_edge2 = '#000812',
    bg_edge  = '#020f19',
    bg       = '#081823',
    bg_mid   = '#253642',
    bg_mid2  = '#435562',

    -- Main foreground: L=85, c=3, h=110
    fg_edge2 = '#f1f3dc',
    fg_edge  = '#e3e5ce',
    fg       = '#d5d7c0',
    fg_mid   = '#b3b59f',
    fg_mid2  = '#91937d',

    -- Initial: L=85, c=8. Real:
    red    = '#ffc0c4',    -- L=84.4, c=7.2, h= 14.4 ( 15)
    orange = '#fcc9a0',    -- L=85.0, c=7.9, h= 60.2 ( 60)
    yellow = '#e0d699',    -- L=84.8, c=7.9, h= 99.9 (100)
    green  = '#b4e3b5',    -- L=84.9, c=7.9, h=145.3 (145)
    cyan   = '#94e6e5',    -- L=85.1, c=8.0, h=194.7 (190)
    azure  = '#a1ddff',    -- L=84.7, c=7.7, h=233.6 (235)
    blue   = '#c8cdff',    -- L=83.8, c=6.9, h=280.3 (280)
    purple = '#f0c3f2',    -- L=85.0, c=8.0, h=324.8 (325)

    -- Initial: L=15, c=8  Real:
    red_bg    = '#410c16', -- L=15.0, c=8.1, h= 14.4 ( 15)
    orange_bg = '#492500', -- L=20.7, c=7.2, h= 60.0 ( 60)
    yellow_bg = '#403700', -- L=23.7, c=7.0, h= 99.1 (100)
    green_bg  = '#002c06', -- L=15.1, c=8.0, h=145.2 (145)
    cyan_bg   = '#004c49', -- L=28.1, c=6.5, h=190.2 (190)
    azure_bg  = '#003851', -- L=22.2, c=6.8, h=235.2 (235)
    blue_bg   = '#1c1b47', -- L=14.8, c=8.0, h=280.0 (280)
    purple_bg = '#351137', -- L=15.0, c=8.1, h=325.5 (325)

    -- Azure accent
    accent    = '#a1ddff',
    accent_bg = '#003851',
  }
else
  -- NOTE: Ideally:
  -- - Fg lightness differs from bg lightness, as in dark background.
  -- - Rainbow colors have the same lightness as foreground.
  --
  -- HOWEVER, it is fairly hard to achieve taking into account all eight
  -- rainbow colors, because there are fewer dark highly saturated (needed for
  -- readability on light bg) colors.
  -- The target is L=20 and c=16, but with `gamut_clip='cusp'` lightness of
  -- most rainbow colors will increase (up to ~40) while chroma will decrease
  -- (up to ~9).
  --
  -- To even things out:
  -- - Increase fg lightness to 25.
  -- - Increase initial rainbow lightness to 30.
  -- - Using L=30 and c=10 as a threshold, hue ranges 70-110 and 170-240 have
  --   no saturated dark colors beyond it. Avoid using them.
  -- - Manually tweak some computed colors to have lightness not be very
  --   different from the target. This improves contrast ratios.

  palette = {
    -- Main background: L=95, c=1, h=90
    bg_edge2 = '#fdfbf2',
    bg_edge  = '#f8f6ee',
    bg       = '#f3f1e9',
    bg_mid   = '#d2d0c9',
    bg_mid2  = '#b2b0a8',

    -- Main foreground: L=25, c=3, h=270
    fg_edge2 = '#0d111f',
    fg_edge  = '#212636',
    fg       = '#34394a',
    fg_mid   = '#4f5567',
    fg_mid2  = '#6c7285',

    -- Initial: L=30, c=16. Real:
    red    = '#870600',     -- L=30.1, c=15.8, h= 30.0 ( 30)
    orange = '#835200',     -- L=40.1, c=10.4, h= 70.2 ( 70); decreased c+L for better contrast ratio
    yellow = '#626200',     -- L=39.8, c=10.5, h=109.8 (110); decreased c+L for better contrast ratio
    green  = '#1d7300',     -- L=40.5, c=15.8, h=140.4 (140); increased c+L to look less like cyan
    cyan   = '#008064',     -- L=46.0, c=10.5, h=170.5 (170); decreased c+L for better contrast ratio
    azure  = '#006699',     -- L=40.7, c=11.3, h=240.8 (240)
    blue   = '#492c93',     -- L=30.0, c=15.9, h=290.0 (290)
    purple = '#780d60',     -- L=30.0, c=16.0, h=339.9 (340)

    -- Initial: L=95, c=6.  Real:
    red_bg    = '#ffd9d1',  -- L=90.1, c=4.4, h= 31.9 ( 30)
    orange_bg = '#ffe5c5',  -- L=92.4, c=5.1, h= 72.9 ( 70)
    yellow_bg = '#f3f5c7',  -- L=95.0, c=6.0, h=109.5 (110)
    green_bg  = '#dcfbd5',  -- L=94.9, c=6.0, h=139.9 (140)
    cyan_bg   = '#caffeb',  -- L=95.1, c=6.0, h=170.0 (170)
    azure_bg  = '#c6e8ff',  -- L=90.0, c=4.8, h=237.6 (240)
    blue_bg   = '#e1ddff',  -- L=89.7, c=4.6, h=290.8 (290)
    purple_bg = '#ffddf6',  -- L=92.2, c=4.9, h=335.3 (340)

    -- Azure accent
    accent    = '#006699',
    accent_bg = '#c6e8ff',
  }
end

require('mini.hues').apply_palette(palette)
vim.g.colors_name = 'minischeme'
