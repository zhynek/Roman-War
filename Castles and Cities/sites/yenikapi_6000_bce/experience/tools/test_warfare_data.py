#!/usr/bin/env python3
import copy
import unittest
from validate_warfare import validate,load
class WarfareData(unittest.TestCase):
    def test_valid(self):self.assertEqual(validate(load('governance'),load('balance')),[])
    def reject(self,key,value):
        b=copy.deepcopy(load('balance'));b['warfare']['tactics'][key]=value
        self.assertTrue(validate(load('governance'),b))
    def test_spacing(self):self.reject('spacing_cm',500)
    def test_fatigue(self):self.reject('fatigue_speed_percent',110)
    def test_time_bound(self):self.reject('enemy_objective_ticks',10000)
    def test_saved_units(self):self.reject('vector_scale',100)
    def test_missing(self):
        b=load('balance');del b['warfare']['tactics']['yield_ticks']
        self.assertTrue(validate(load('governance'),b))
    def test_profile(self):
        g=load('governance');g['warfare']['profile']='other'
        self.assertTrue(validate(g,load('balance')))
if __name__=='__main__':unittest.main()
