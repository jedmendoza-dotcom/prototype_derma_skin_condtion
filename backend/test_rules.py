import unittest, symptom_rules as r

class T(unittest.TestCase):
    def test_sum_one(self):
        p = r.rule_probs("18-30", "1_3m", 0, False, False, "dark brown patches on my cheeks")
        self.assertAlmostEqual(sum(p.values()), 1.0)
    def test_melasma(self):
        p = r.rule_probs("31-45", "gt_3m", 0, False, False, "brown patches on my face after the sun")
        self.assertEqual(max(p, key=p.get), "melasma")
    def test_scabies(self):
        p = r.rule_probs("18-30", "1_2w", 9, False, False, "very itchy at night, my family is also itchy")
        self.assertEqual(max(p, key=p.get), "scabies")
    def test_impetigo(self):
        p = r.rule_probs("2-5", "1_3d", 4, True, False, "sores with honey crust")
        self.assertEqual(max(p, key=p.get), "impetigo")
    def test_cebuano_acne(self):
        p = r.rule_probs("13-17", "1_3m", 1, False, False, "daghan tigyawat sa akong nawong")
        self.assertEqual(max(p, key=p.get), "acne")
    def test_cap(self):
        c = r.combine({"acne": .9, "eczema": .1}, None)
        self.assertLessEqual(max(c.values()), r.RULES_ONLY_CAP)
    def test_model_blend(self):
        c = r.combine({"acne": .5, "eczema": .5}, {"acne": 1.0})
        self.assertAlmostEqual(c["acne"], 0.85)
    def test_model_extra_label(self):
        c = r.combine({"acne": .5, "eczema": .5}, {"psoriasis": 0.9, "other": 0.1})
        self.assertIn("psoriasis", c)
        self.assertGreater(c["psoriasis"], c["acne"])
if __name__ == "__main__": unittest.main()