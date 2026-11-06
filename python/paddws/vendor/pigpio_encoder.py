# Classe per encoder rotativo basata sulla libreria pigpio
# versione: 0.2.2 (inclusa da github.com/vash3d/pigpio_encoder, GPLv3)
# Correzioni locali: niente fallback con MagicMock all'import (pigpio mancante
# è gestito da paddws.hardware), sw_gpio vale None di default, callback opzionali.

import pigpio

import time

# Stati
dt_gpio1 = 'D'  # dt_gpio alto
dt_gpio0 = 'd'  # dt_gpio basso
clk_gpio1 = 'C'  # clk_gpio alto
clk_gpio0 = 'c'  # clk_gpio basso

# Sequenze di stati
SEQUENCE_UP = dt_gpio1 + clk_gpio1 + dt_gpio0 + clk_gpio0
SEQUENCE_DOWN = clk_gpio1 + dt_gpio1 + clk_gpio0 + dt_gpio0


class Rotary:

    sequence = ''

    # Valori di default dell'encoder rotativo
    min = 0
    max = 100
    scale = 1
    debounce = 300
    _counter = 0
    last_counter = 0
    rotary_callback = None

    # Valori di default del pulsante
    sw_gpio_debounce = 300
    long_press_opt = False
    sw_gpio_short_callback = None
    sw_gpio_long_callback = None
    wait_time = time.time()
    long = False
    sw_gpio = None

    def __init__(self, clk_gpio=None, dt_gpio=None, sw_gpio=None):
        if not (clk_gpio and dt_gpio):
            raise BaseException("clk_gpio and dt_gpio pin must be specified!")

        self.pi = pigpio.pi()
        self.clk_gpio = clk_gpio
        self.dt_gpio = dt_gpio
        self.pi.set_glitch_filter(self.clk_gpio, self.debounce)
        self.pi.set_glitch_filter(self.dt_gpio, self.debounce)
        if sw_gpio is not None:
            self.sw_gpio = sw_gpio
            self.pi.set_pull_up_down(self.sw_gpio, pigpio.PUD_UP)
            self.pi.set_glitch_filter(self.sw_gpio, self.sw_gpio_debounce)
        self.setup_pigpio_callbacks()

    def setup_pigpio_callbacks(self):
        self.pi.callback(self.clk_gpio, pigpio.FALLING_EDGE, self.clk_gpio_fall)
        self.pi.callback(self.clk_gpio, pigpio.RISING_EDGE, self.clk_gpio_rise)
        self.pi.callback(self.dt_gpio, pigpio.FALLING_EDGE, self.dt_gpio_fall)
        self.pi.callback(self.dt_gpio, pigpio.RISING_EDGE, self.dt_gpio_rise)
        if self.sw_gpio is not None:
            self.pi.callback(self.sw_gpio, pigpio.FALLING_EDGE, self.sw_gpio_fall)
            self.pi.callback(self.sw_gpio, pigpio.RISING_EDGE, self.sw_gpio_rise)

    @property
    def counter(self):
        return self._counter

    @counter.setter
    def counter(self, value):
        if self._counter != value:
            self._counter = value
            if self.rotary_callback:
                self.rotary_callback(self._counter)

    def clk_gpio_fall(self, gpio, level, tick):
        if len(self.sequence) > 2:
            self.sequence = ''
        self.sequence += clk_gpio1

    def clk_gpio_rise(self, gpio, level, tick):
        self.sequence += clk_gpio0
        if self.sequence == SEQUENCE_UP:
            if self.counter < self.max:
                self.counter += self.scale
            self.sequence = ''

    def dt_gpio_fall(self, gpio, level, tick):
        if len(self.sequence) > 2:
            self.sequence = ''
        self.sequence += dt_gpio1

    def dt_gpio_rise(self, gpio, level, tick):
        self.sequence += dt_gpio0
        if self.sequence == SEQUENCE_DOWN:
            if self.counter > self.min:
                self.counter -= self.scale
            self.sequence = ''

    def sw_gpio_rise(self, gpio, level, tick):
        if self.long_press_opt:
            if not self.long:
                self.short_press()

    def sw_gpio_fall(self, gpio, level, tick):
        if self.long_press_opt:
            self.long = False
            press_time = time.time()
            while self.pi.read(self.sw_gpio) == 0:
                self.wait_time = time.time()
                time.sleep(0.1)
                if self.wait_time - press_time > 1.5:
                    self.long_press()
                    self.long = True
                    break
        else:
            self.short_press()

    def setup_rotary(self, **kwargs):
        # la callback di rotazione va impostata per prima: la proprietà self.counter dipende da essa
        if 'rotary_callback' in kwargs:
            self.rotary_callback = kwargs['rotary_callback']
        if 'min' in kwargs:
            self.min = kwargs['min']
            self.counter = self.min
            self.last_counter = self.min
        if 'max' in kwargs:
            self.max = kwargs['max']
        if 'scale' in kwargs:
            self.scale = kwargs['scale']
        if 'debounce' in kwargs:
            self.debounce = kwargs['debounce']
            self.pi.set_glitch_filter(self.clk_gpio, self.debounce)
            self.pi.set_glitch_filter(self.dt_gpio, self.debounce)

    def setup_switch(self, **kwargs):
        # la callback va impostata per prima: ad esempio la proprietà self.counter dipende da essa
        if 'debounce' in kwargs:
            self.sw_gpio_debounce = kwargs['debounce']
        if 'long_press' in kwargs:
            self.long_press_opt = kwargs['long_press']
        if 'sw_gpio_short_callback' in kwargs:
            self.sw_gpio_short_callback = kwargs['sw_gpio_short_callback']
        if 'sw_gpio_long_callback' in kwargs:
            self.sw_gpio_long_callback = kwargs['sw_gpio_long_callback']

    def watch(self):
        """
        Semplice funzione di comodo per avere un ciclo di attesa
        """
        while True:
            time.sleep(10)

    def short_press(self):
        if self.sw_gpio_short_callback:
            self.sw_gpio_short_callback()

    def long_press(self):
        if self.sw_gpio_long_callback:
            self.sw_gpio_long_callback()
